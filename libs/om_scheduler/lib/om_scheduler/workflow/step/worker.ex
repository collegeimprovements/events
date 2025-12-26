defmodule OmScheduler.Workflow.Step.Worker do
  @moduledoc """
  Convenience macro for implementing workflow step workers.

  Provides a clean interface for creating step modules with:
  - Behaviour implementation
  - Default rollback (no-op)
  - Default schedule

  ## Usage

      defmodule MyApp.Steps.SendWelcomeEmail do
        use OmScheduler.Workflow.Step.Worker

        @impl true
        def perform(%{user_id: user_id} = ctx) do
          case Mailer.send_welcome(user_id) do
            :ok -> {:ok, %{email_sent: true}}
            {:error, reason} -> {:error, reason}
          end
        end

        # Optional: define rollback for saga compensation
        @impl true
        def rollback(ctx) do
          Mailer.cancel_pending(ctx.user_id)
          :ok
        end

        # Optional: override default schedule
        @impl true
        def schedule do
          [
            timeout: {2, :minutes},
            max_retries: 5
          ]
        end
      end

  ## Using in Workflows

  Worker modules can be used directly in workflows:

      defmodule MyApp.OnboardingWorkflow do
        use OmScheduler.Workflow, name: :onboarding

        alias MyApp.Steps.{CreateUser, SendWelcomeEmail}

        @decorate step()
        def create_user(ctx), do: CreateUser.perform(ctx)

        # Or reference directly in builder API
        # Workflow.step(:send_welcome, SendWelcomeEmail, after: :create_user)
      end
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour OmScheduler.Workflow.Step.Behaviour

      @impl OmScheduler.Workflow.Step.Behaviour
      def rollback(_ctx), do: :ok

      @impl OmScheduler.Workflow.Step.Behaviour
      def schedule, do: []

      defoverridable rollback: 1, schedule: 0
    end
  end
end
