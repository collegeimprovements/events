defmodule OmScheduler.Workflow.Decorator.Step do
  @moduledoc """
  Decorator implementation for `@decorate step(...)`.

  Collects workflow step definitions at compile time and registers them
  with the workflow module.

  ## Usage

      defmodule MyApp.Onboarding do
        use OmScheduler.Workflow, name: :user_onboarding

        @decorate step()
        def create_account(ctx), do: {:ok, %{user_id: Users.create!(ctx.email)}}

        @decorate step(after: :create_account, timeout: {5, :minutes})
        def send_welcome(ctx), do: Mailer.send_welcome(ctx.user_id)

        @decorate step(after: :send_welcome, rollback: :cleanup_welcome)
        def setup_profile(ctx), do: Profiles.create!(ctx.user_id)

        def cleanup_welcome(ctx), do: Mailer.cancel_welcome(ctx.user_id)
      end

  ## Options

  - `:after` - Step(s) this depends on (all must complete)
  - `:after_any` - Step(s) where any completing triggers this step
  - `:after_group` - Wait for all steps in a parallel group
  - `:after_graft` - Wait for graft expansion to complete
  - `:group` - Add to a parallel group for fan-out
  - `:when` - Condition function `(ctx -> boolean)`
  - `:rollback` - Function name for saga-pattern compensation
  - `:timeout` - Step timeout (overrides workflow default)
  - `:max_retries` - Max retries (overrides workflow default)
  - `:retry_delay` - Retry delay (overrides workflow default)
  - `:retry_backoff` - `:fixed`, `:exponential`, or `:linear`
  - `:retry_max_delay` - Maximum delay for exponential backoff
  - `:retry_jitter` - Add jitter to retry delays
  - `:retry_on` - Error types to retry on
  - `:no_retry_on` - Error types to never retry
  - `:on_error` - `:fail`, `:skip`, or `:continue`
  - `:await_approval` - Pause for human approval
  - `:cancellable` - Can be cancelled (default: true)
  - `:context_key` - Key to store result (defaults to function name)
  - `:circuit_breaker` - Circuit breaker name
  - `:circuit_breaker_opts` - Circuit breaker options
  """

  @doc """
  Decorator transformation for workflow step functions.

  Called by the decorator system at compile time.
  """
  def step(opts \\ [], body, context) do
    %{module: module, name: function_name, arity: arity} = context

    # Only decorate 1-arity functions (receive context)
    if arity != 1 do
      raise CompileError,
        description: "@decorate step can only be used on 1-arity functions that receive context",
        file: context.file,
        line: context.line
    end

    # Build step spec
    step_spec = {function_name, {:function, module, function_name}, opts}

    # Register the step spec in module attribute
    quote do
      @__workflow_steps__ unquote(Macro.escape(step_spec))

      # Return the original body unchanged
      unquote(body)
    end
  end
end
