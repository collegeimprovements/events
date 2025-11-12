defmodule Events.Contracts.Adapter do
  @moduledoc """
  Base behaviour for service adapter implementations.

  Adapters are concrete implementations of service behaviours. They handle
  the actual integration with external systems (AWS, Redis, file system, etc.)
  or provide mock/test implementations.

  ## Adapter Types

  - **Real Adapters**: Production implementations (e.g., ExAwsAdapter, RedisAdapter)
  - **Mock Adapters**: In-memory mocks for testing (e.g., MockAdapter)
  - **Local Adapters**: Local alternatives for development (e.g., LocalFileAdapter)

  ## Design Principles

  - **Stateless**: Adapters should be stateless; pass context/config per call
  - **Error Handling**: Return standard {:ok, result} | {:error, reason} tuples
  - **Resource Management**: Clean up resources, handle timeouts
  - **Testability**: Easy to test in isolation

  ## Example

      defmodule MyApp.Services.Storage.S3Adapter do
        @behaviour MyApp.Services.Storage
        @behaviour Events.Contracts.Adapter

        @impl true
        def adapter_name, do: :s3

        @impl true
        def adapter_config(opts) do
          %{
            bucket: Keyword.fetch!(opts, :bucket),
            region: Keyword.get(opts, :region, "us-east-1")
          }
        end

        @impl MyApp.Services.Storage
        def upload(context, key, data) do
          # Implementation
        end
      end
  """

  @doc """
  Returns the adapter name as an atom.

  This is used for adapter selection and logging.
  """
  @callback adapter_name() :: atom()

  @doc """
  Validates and transforms adapter configuration.

  Takes raw options and returns a validated config map or raises on invalid config.
  """
  @callback adapter_config(opts :: keyword()) :: map()

  @doc """
  Helper to get adapter module from atom name.

  ## Examples

      iex> Adapter.resolve(:s3, MyApp.Services.Storage)
      MyApp.Services.Storage.S3Adapter

      iex> Adapter.resolve(:mock, MyApp.Services.Storage)
      MyApp.Services.Storage.MockAdapter
  """
  @spec resolve(adapter_name :: atom(), base_module :: module()) :: module()
  def resolve(adapter_name, base_module) do
    adapter_module_name =
      adapter_name
      |> Atom.to_string()
      |> Macro.camelize()

    Module.concat([base_module, "#{adapter_module_name}Adapter"])
  end

  @doc """
  Helper to check if a module implements the Adapter behaviour.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    :attributes
    |> module.__info__()
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(__MODULE__)
  end
end
