defmodule OmBehaviours.Adapter do
  @moduledoc """
  Base behaviour for service adapter implementations.

  Adapters are concrete implementations of service behaviours. They handle
  the actual integration with external systems (AWS, Redis, file system, etc.)
  or provide mock/test implementations.

  ## Adapter Types

  - **Production**: Real implementations (e.g., S3, Redis)
  - **Mock**: In-memory mocks for testing
  - **Local**: Local alternatives for development (e.g., LocalFile)

  ## Design Principles

  - **Stateless**: Adapters should be stateless; pass context/config per call
  - **Error Handling**: Return standard {:ok, result} | {:error, reason} tuples
  - **Resource Management**: Clean up resources, handle timeouts
  - **Testability**: Easy to test in isolation

  ## Example

      defmodule MyApp.Services.Storage.S3 do
        @behaviour MyApp.Services.Storage
        @behaviour OmBehaviours.Adapter

        @impl OmBehaviours.Adapter
        def adapter_name, do: :s3

        @impl OmBehaviours.Adapter
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

  This is used for adapter selection and logging. The name should be short,
  descriptive, and unique within the service's adapter ecosystem.

  ## Examples

      defmodule MyApp.Storage.S3 do
        @behaviour OmBehaviours.Adapter

        @impl true
        def adapter_name, do: :s3
      end

      defmodule MyApp.Storage.Local do
        @behaviour OmBehaviours.Adapter

        @impl true
        def adapter_name, do: :local
      end

      defmodule MyApp.Storage.Mock do
        @behaviour OmBehaviours.Adapter

        @impl true
        def adapter_name, do: :mock
      end
  """
  @callback adapter_name() :: atom()

  @doc """
  Validates and transforms adapter configuration.

  Takes raw options (typically from application config) and returns a validated
  config map. This is where you convert keyword lists to structured maps, apply
  defaults, and validate required fields.

  Raises an error if configuration is invalid.

  ## Examples

      defmodule MyApp.Storage.S3 do
        @behaviour OmBehaviours.Adapter

        @impl true
        def adapter_config(opts) do
          %{
            bucket: Keyword.fetch!(opts, :bucket),
            region: Keyword.get(opts, :region, "us-east-1"),
            acl: Keyword.get(opts, :acl, :private),
            timeout: Keyword.get(opts, :timeout, 30_000)
          }
        end
      end

      # Usage
      config = MyApp.Storage.S3.adapter_config(bucket: "my-bucket", region: "us-west-2")
      #=> %{bucket: "my-bucket", region: "us-west-2", acl: :private, timeout: 30_000}

      # Missing required field raises
      MyApp.Storage.S3.adapter_config([])
      #=> ** (KeyError) key :bucket not found in: []
  """
  @callback adapter_config(opts :: keyword()) :: map()

  @doc """
  Helper to get adapter module from atom name.

  Converts an adapter name atom (like `:s3`) into the full module name by camelizing
  the name and concatenating it with the base module. This is useful for dynamic
  adapter resolution at runtime.

  ## Parameters

  - `adapter_name` - The adapter identifier as an atom (e.g., `:s3`, `:local`, `:mock`)
  - `base_module` - The base module namespace (e.g., `MyApp.Storage`)

  ## Returns

  The fully qualified adapter module name.

  ## Examples

      # S3 adapter
      iex> OmBehaviours.Adapter.resolve(:s3, MyApp.Storage)
      MyApp.Storage.S3

      # Local file adapter
      iex> OmBehaviours.Adapter.resolve(:local, MyApp.Storage)
      MyApp.Storage.Local

      # Mock adapter
      iex> OmBehaviours.Adapter.resolve(:mock, MyApp.Storage)
      MyApp.Storage.Mock

      # Multi-word adapter names get camelized
      iex> OmBehaviours.Adapter.resolve(:google_cloud, MyApp.Storage)
      MyApp.Storage.GoogleCloud

  ## Real-World Usage

      # Configuration-based adapter selection
      defmodule MyApp.Storage do
        def adapter do
          adapter_name = Application.get_env(:my_app, :storage_adapter, :local)
          OmBehaviours.Adapter.resolve(adapter_name, __MODULE__)
        end

        def upload(key, data) do
          adapter().upload(key, data)
        end
      end

      # Then in config/dev.exs
      config :my_app, storage_adapter: :local

      # And in config/prod.exs
      config :my_app, storage_adapter: :s3
  """
  @spec resolve(adapter_name :: atom(), base_module :: module()) :: module()
  def resolve(adapter_name, base_module) do
    adapter_module_name =
      adapter_name
      |> Atom.to_string()
      |> Macro.camelize()

    Module.concat([base_module, adapter_module_name])
  end

  @doc """
  Helper to check if a module implements the Adapter behaviour.

  ## Parameters

  - `module` - The module to check

  ## Returns

  `true` if the module implements `OmBehaviours.Adapter`, `false` otherwise.

  ## Examples

      defmodule MyApp.Storage.S3 do
        @behaviour OmBehaviours.Adapter
        # ... implementations
      end

      iex> OmBehaviours.Adapter.implements?(MyApp.Storage.S3)
      true

      iex> OmBehaviours.Adapter.implements?(SomeOtherModule)
      false

  ## Real-World Usage

      # Validate adapter at compile time
      defmodule MyApp.StorageService do
        @behaviour OmBehaviours.Adapter
        @adapter MyApp.Storage.S3

        unless OmBehaviours.Adapter.implements?(@adapter) do
          raise CompileError, description: "MyApp.Storage.S3 must implement OmBehaviours.Adapter"
        end

        def upload(key, data), do: @adapter.upload(key, data)
      end
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    OmBehaviours.implements?(module, __MODULE__)
  end
end
