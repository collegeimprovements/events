if Code.ensure_loaded?(Effect.Builder) do
  # Also handle {:effect_with_context, effect, context_fn} tuples
  # This is added to the Tuple implementation below

  defimpl OmScheduler.Workflow.Step.Executable, for: Effect.Builder do
    @moduledoc """
    Implementation of `Step.Executable` protocol for `Effect.Builder`.

    This enables using Effect workflows as step jobs in OmScheduler workflows,
    bridging the two systems for powerful composition.

    ## Usage

    ```elixir
    # Define an Effect
    payment_effect = Effect.new(:payment)
      |> Effect.step(:authorize, &authorize/1)
      |> Effect.step(:capture, &capture/1, rollback: &void/1)

    # Use in a Workflow
    Workflow.new(:order)
    |> Workflow.step(:validate, &validate/1)
    |> Workflow.effect(:payment, payment_effect, after: :validate)
    |> Workflow.step(:fulfill, &fulfill/1, after: :payment)
    ```

    ## Context Mapping

    The workflow context is passed directly to the Effect. Effect results
    are merged back into the workflow context.

    ## Error Handling

    - Effect `{:ok, map}` → Workflow `{:ok, map}`
    - Effect `{:error, Error.t()}` → Workflow `{:error, reason}`
    - Effect `{:halted, reason}` → Workflow `{:skip, reason}`

    ## Rollbacks

    Effects handle their own rollbacks internally via the saga pattern.
    When an Effect step fails, its internal rollbacks are executed before
    the error propagates to the parent workflow. The parent workflow
    may then execute its own rollbacks for previous steps.

    ## Checkpoints

    If the Effect reaches a checkpoint, it returns `{:await, checkpoint_info}`
    which the workflow can handle as a human-in-the-loop pause point.
    """

    require Logger

    @doc """
    Executes the Effect with the workflow context.

    The Effect's internal context accumulation is isolated - only the final
    merged context is returned to the parent workflow.
    """
    @spec execute(Effect.Builder.t(), map()) :: term()
    def execute(%Effect.Builder{} = effect, context) do
      try do
        case Effect.run(effect, context) do
          {:ok, result_context} ->
            # Return the accumulated context from the effect
            {:ok, result_context}

          {:error, %Effect.Error{} = error} ->
            # Extract the underlying reason for the workflow
            Logger.warning(
              "[Effect→Workflow] Effect #{inspect(effect.name)} failed: #{inspect(error.reason)}"
            )

            {:error, {:effect_failed, effect.name, error.reason}}

          {:error, reason} ->
            {:error, {:effect_failed, effect.name, reason}}

          {:halted, reason} ->
            # Effect halted gracefully - treat as skip in workflow
            {:skip, {:effect_halted, effect.name, reason}}

          {:checkpoint, execution_id, checkpoint_name, checkpoint_context} ->
            # Effect reached a checkpoint - translate to workflow await
            {:await,
             %{
               type: :effect_checkpoint,
               effect_name: effect.name,
               execution_id: execution_id,
               checkpoint: checkpoint_name,
               context: checkpoint_context
             }}
        end
      rescue
        e ->
          Logger.error(
            "[Effect→Workflow] Effect #{inspect(effect.name)} raised: #{Exception.message(e)}"
          )

          {:error, {:exception, e, __STACKTRACE__}}
      catch
        :exit, reason ->
          {:error, {:exit, reason}}

        :throw, value ->
          {:error, {:throw, value}}
      end
    end

    @doc """
    Effects handle their own rollbacks internally.

    When an Effect is used as a workflow step, its internal saga-pattern
    rollbacks are executed automatically when any step within the Effect
    fails. Therefore, we don't need to execute additional rollbacks at
    the workflow level for the Effect itself.

    If you need workflow-level rollback for an Effect step, wrap the
    Effect in a function and provide a rollback in the workflow step options.
    """
    @spec rollback(Effect.Builder.t(), map()) :: :ok | {:error, term()}
    def rollback(%Effect.Builder{} = _effect, _context) do
      # Effects handle their own rollbacks internally via saga pattern
      # The rollbacks are already executed when Effect.run returns {:error, _}
      :ok
    end

    @doc """
    Returns false because Effects handle rollbacks internally.

    If you need workflow-level rollback behavior, wrap the Effect
    execution in a function and provide explicit rollback:

    ```elixir
    Workflow.step(:payment, fn ctx ->
      case Effect.run(payment_effect, ctx) do
        {:ok, result} -> {:ok, result}
        {:error, _} = error -> error
      end
    end, rollback: fn ctx -> reverse_payment(ctx) end)
    ```
    """
    @spec has_rollback?(Effect.Builder.t()) :: boolean()
    def has_rollback?(%Effect.Builder{} = _effect), do: false
  end
end
