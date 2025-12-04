defmodule Events.Infra.Scheduler.Workflow.Decorator.Workflow do
  @moduledoc """
  Decorator implementation for `@decorate workflow(:name, ...)`.

  Embeds a nested workflow as a step within the parent workflow.

  ## Usage

      defmodule MyApp.Notification do
        use Events.Infra.Scheduler.Workflow, name: :send_notification

        @decorate step()
        def format(ctx), do: {:ok, %{message: format_message(ctx.template, ctx.data)}}

        @decorate step(after: :format)
        def send(ctx), do: Notifier.send(ctx.channel, ctx.message)
      end

      defmodule MyApp.UserOnboarding do
        use Events.Infra.Scheduler.Workflow, name: :user_onboarding

        @decorate step()
        def create_user(ctx), do: {:ok, %{user: Users.create!(ctx)}}

        # Embed entire workflow as a step
        @decorate workflow(:send_notification, after: :create_user)
        def notify_user(_ctx), do: %{template: :welcome, channel: :email}

        @decorate step(after: :notify_user)
        def complete(ctx), do: {:ok, %{onboarded: true}}
      end

  ## How Nested Workflows Work

  1. The decorated function is called to produce context for the nested workflow
  2. The nested workflow executes with the parent's context merged with the returned context
  3. When the nested workflow completes, its final context is merged back into parent
  4. Parent steps depending on this step wait for the nested workflow to complete

  ## Options

  - `:after` - Step(s) this nested workflow depends on
  - `:after_any` - Any of these steps completing triggers the nested workflow
  - `:timeout` - Total timeout for the nested workflow execution
  - `:on_error` - How to handle nested workflow failure
  """

  @doc """
  Decorator transformation for nested workflow steps.

  Called by the decorator system at compile time.
  """
  def workflow(nested_workflow_name, opts \\ [], body, context) do
    %{module: module, name: function_name, arity: arity} = context

    if arity != 1 do
      raise CompileError,
        description:
          "@decorate workflow can only be used on 1-arity functions that receive context",
        file: context.file,
        line: context.line
    end

    unless is_atom(nested_workflow_name) do
      raise CompileError,
        description: "@decorate workflow requires a workflow name atom as first argument",
        file: context.file,
        line: context.line
    end

    nested_spec = {function_name, nested_workflow_name, opts}

    quote do
      @__workflow_nested__ unquote(Macro.escape(nested_spec))

      # Also register as a step with special job type
      @__workflow_steps__ {
        unquote(function_name),
        {:nested_workflow, unquote(nested_workflow_name), unquote(module), unquote(function_name)},
        unquote(opts)
      }

      unquote(body)
    end
  end
end
