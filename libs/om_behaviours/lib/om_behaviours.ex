defmodule OmBehaviours do
  @moduledoc """
  Common behaviour patterns for Elixir applications.

  Provides base behaviours for:
  - **Adapter** - Service adapter implementations
  - **Service** - Core service modules
  - **Builder** - Fluent builder patterns

  ## Usage

      # Adapter pattern
      defmodule MyApp.Storage.S3Adapter do
        @behaviour MyApp.Storage
        @behaviour OmBehaviours.Adapter

        @impl OmBehaviours.Adapter
        def adapter_name, do: :s3

        @impl OmBehaviours.Adapter
        def adapter_config(opts), do: %{bucket: opts[:bucket]}
      end

      # Service pattern
      defmodule MyApp.NotificationService do
        @behaviour OmBehaviours.Service

        @impl true
        def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
      end

      # Builder pattern
      defmodule MyApp.QueryBuilder do
        use OmBehaviours.Builder

        defstruct [:query, :filters]

        @impl true
        def new(query, _opts), do: %__MODULE__{query: query, filters: []}

        @impl true
        def compose(builder, {:filter, field, value}) do
          %{builder | filters: [{field, value} | builder.filters]}
        end

        @impl true
        def build(builder), do: apply_filters(builder.query, builder.filters)
      end
  """

  @doc """
  Checks if a module implements a specific behaviour.

  ## Examples

      OmBehaviours.implements?(MyAdapter, OmBehaviours.Adapter)
      #=> true
  """
  @spec implements?(module(), module()) :: boolean()
  def implements?(module, behaviour) do
    :attributes
    |> module.__info__()
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(behaviour)
  rescue
    _ -> false
  end
end
