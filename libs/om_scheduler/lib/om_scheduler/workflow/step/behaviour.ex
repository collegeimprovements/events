defmodule OmScheduler.Workflow.Step.Behaviour do
  @moduledoc """
  Behaviour for workflow step workers.

  Implement this behaviour for complex workflow steps that need:
  - Configuration via `schedule/0`
  - Custom rollback logic via `rollback/1`
  - Clean module-based organization

  ## Usage

      defmodule MyApp.Steps.CreateUser do
        use OmScheduler.Workflow.Step.Worker

        @impl true
        def perform(%{email: email} = ctx) do
          case Users.create(email) do
            {:ok, user} -> {:ok, %{user_id: user.id}}
            {:error, reason} -> {:error, reason}
          end
        end

        @impl true
        def rollback(%{user_id: user_id} = ctx) do
          Users.delete(user_id)
          :ok
        end
      end

  ## Callbacks

  - `perform/1` - Execute the step (required)
  - `rollback/1` - Compensate on workflow failure (optional)
  - `schedule/0` - Return step configuration (optional)

  ## Return Values from perform/1

  - `{:ok, map}` - Success, merge map into context
  - `:ok` - Success, no context changes
  - `{:error, reason}` - Failure (triggers retry or error handling)
  - `{:skip, reason}` - Skip step, continue workflow
  - `{:await, opts}` - Pause for human approval
  - `{:expand, steps}` - Graft expansion (for graft steps)
  - `{:snooze, duration}` - Pause and retry after duration
  """

  @type context :: map()
  @type result ::
          {:ok, map()}
          | :ok
          | {:error, term()}
          | {:skip, term()}
          | {:await, keyword()}
          | {:expand, [{atom(), function()}]}
          | {:snooze, pos_integer() | {pos_integer(), atom()}}

  @doc """
  Executes the step with the given context.

  The context contains accumulated results from previous steps
  plus any initial context provided when starting the workflow.
  """
  @callback perform(context()) :: result()

  @doc """
  Rolls back the step's effects.

  Called during saga-pattern compensation when a downstream step fails.
  The context contains all accumulated results up to and including
  this step's result.

  Should return `:ok` on success or `{:error, reason}` on failure.
  Rollback failures are logged but don't prevent other rollbacks.
  """
  @callback rollback(context()) :: :ok | {:error, term()}

  @doc """
  Returns configuration for this step.

  Used when the step is registered as a worker module.

  ## Options

  - `:timeout` - Step timeout
  - `:max_retries` - Max retry attempts
  - `:retry_delay` - Delay between retries
  - `:retry_backoff` - Backoff strategy
  - `:on_error` - Error handling mode

  ## Example

      def schedule do
        [
          timeout: {5, :minutes},
          max_retries: 5,
          retry_backoff: :exponential
        ]
      end
  """
  @callback schedule() :: keyword()

  @optional_callbacks [rollback: 1, schedule: 0]
end
