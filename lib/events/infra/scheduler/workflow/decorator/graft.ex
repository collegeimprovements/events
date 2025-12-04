defmodule Events.Infra.Scheduler.Workflow.Decorator.Graft do
  @moduledoc """
  Decorator implementation for `@decorate graft(...)`.

  Defines a graft placeholder that can be dynamically expanded at runtime
  into multiple parallel steps.

  ## Usage

      defmodule MyApp.BatchProcessor do
        use Events.Infra.Scheduler.Workflow, name: :batch_processor

        @decorate step()
        def fetch_batch(ctx), do: {:ok, %{items: Database.fetch_batch(ctx.batch_id)}}

        @decorate graft(after: :fetch_batch)
        def process_items(ctx) do
          # Return expansion: each item becomes a parallel step
          expansions = Enum.map(ctx.items, &build_expansion/1)
          {:expand, expansions}
        end

        defp build_expansion(item) do
          {:"process_item_\#{item.id}", fn _ -> process_one(item) end}
        end

        @decorate step(after_graft: :process_items)
        def summarize(ctx), do: {:ok, %{summary: aggregate_results(ctx)}}
      end

  ## How Grafting Works

  1. The graft function is called during workflow execution
  2. It returns `{:expand, expansions}` where expansions is a list of `{name, job}` tuples
  3. The workflow engine creates new parallel steps from the expansions
  4. Steps depending on `after_graft: :graft_name` wait for all expanded steps to complete

  ## Options

  - `:after` - Step(s) this graft depends on
  - `:after_any` - Any of these steps completing triggers the graft
  - `:timeout` - Timeout for the graft function itself
  """

  @doc """
  Decorator transformation for graft functions.

  Called by the decorator system at compile time.
  """
  def graft(opts \\ [], body, context) do
    %{module: module, name: function_name, arity: arity} = context

    if arity != 1 do
      raise CompileError,
        description: "@decorate graft can only be used on 1-arity functions that receive context",
        file: context.file,
        line: context.line
    end

    graft_spec = {function_name, opts}

    quote do
      @__workflow_grafts__ unquote(Macro.escape(graft_spec))

      # Also register as a step that returns the expansion
      @__workflow_steps__ {
        unquote(function_name),
        {:function, unquote(module), unquote(function_name)},
        Keyword.put(unquote(opts), :is_graft, true)
      }

      unquote(body)
    end
  end
end
