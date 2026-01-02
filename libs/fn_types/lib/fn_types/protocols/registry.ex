defmodule FnTypes.Protocols.Registry do
  @moduledoc """
  Registry for protocol implementations with introspection capabilities.

  Provides utilities for discovering, listing, and verifying protocol
  implementations across the codebase.

  ## Design Principles

  - **Introspection** - List all protocols and their implementations
  - **Verification** - Check that implementations are complete
  - **Discovery** - Find implementations at compile-time and runtime
  - **Documentation** - Generate protocol documentation

  ## Quick Reference

  | Function | Use Case |
  |----------|----------|
  | `list_protocols/0` | List all known protocols |
  | `list_implementations/1` | List implementations for a protocol |
  | `verify/1` | Verify implementation completeness |
  | `summary/0` | Get summary of all protocols |

  ## Configuration

  Configure known protocols in your application config:

      config :fn_types, FnTypes.Protocols.Registry,
        protocols: [
          FnTypes.Protocols.Recoverable,
          FnTypes.Protocols.Normalizable,
          FnTypes.Protocols.Identifiable,
          MyApp.Protocols.CustomProtocol
        ]

  ## Usage

      alias FnTypes.Protocols.Registry

      # List all protocols
      Registry.list_protocols()
      #=> [FnTypes.Protocols.Recoverable, FnTypes.Protocols.Normalizable, ...]

      # List implementations for a protocol
      Registry.list_implementations(FnTypes.Protocols.Recoverable)
      #=> [
      #     {Postgrex.Error, FnTypes.Protocols.Recoverable.Postgrex.Error},
      #     {Ecto.Changeset, FnTypes.Protocols.Recoverable.Ecto.Changeset},
      #     ...
      #   ]

      # Verify all implementations
      Registry.verify_all()
      #=> :ok | {:error, [missing: [...], incomplete: [...]]}

      # Get protocol summary
      Registry.summary()
      #=> %{
      #     Recoverable: %{implementations: 12, coverage: :full},
      #     Normalizable: %{implementations: 8, coverage: :full},
      #     ...
      #   }
  """

  # Default protocols in the FnTypes namespace
  @default_protocols [
    FnTypes.Protocols.Recoverable,
    FnTypes.Protocols.Normalizable,
    FnTypes.Protocols.Identifiable
  ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Lists all known protocols in the system.

  Returns protocols configured via application config, falling back to defaults.

  ## Examples

      Registry.list_protocols()
      #=> [FnTypes.Protocols.Recoverable, FnTypes.Protocols.Normalizable, ...]
  """
  @spec list_protocols() :: [module()]
  def list_protocols do
    known_protocols()
    |> Enum.filter(&Code.ensure_loaded?/1)
  end

  @doc """
  Lists all implementations for a given protocol.

  Returns a list of `{for_type, implementation_module}` tuples.

  ## Examples

      Registry.list_implementations(FnTypes.Protocols.Recoverable)
      #=> [
      #     {Postgrex.Error, FnTypes.Protocols.Recoverable.Postgrex.Error},
      #     {Any, FnTypes.Protocols.Recoverable.Any},
      #     ...
      #   ]
  """
  @spec list_implementations(module()) :: [{module(), module()}]
  def list_implementations(protocol) when is_atom(protocol) do
    if protocol_module?(protocol) do
      case get_consolidated_impls(protocol) do
        {:ok, impls} -> impls
        :error -> discover_implementations(protocol)
      end
    else
      []
    end
  end

  @doc """
  Returns the implementation module for a specific type.

  ## Examples

      Registry.get_implementation(FnTypes.Protocols.Recoverable, Postgrex.Error)
      #=> {:ok, FnTypes.Protocols.Recoverable.Postgrex.Error}

      Registry.get_implementation(FnTypes.Protocols.Recoverable, UnknownStruct)
      #=> {:error, :not_found}
  """
  @spec get_implementation(module(), module()) :: {:ok, module()} | {:error, :not_found}
  def get_implementation(protocol, for_type) do
    impls = list_implementations(protocol)

    case List.keyfind(impls, for_type, 0) do
      {^for_type, impl_module} -> {:ok, impl_module}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Checks if a type has an implementation for a protocol.

  ## Examples

      Registry.implemented?(FnTypes.Protocols.Recoverable, Postgrex.Error)
      #=> true

      Registry.implemented?(FnTypes.Protocols.Recoverable, MyApp.CustomStruct)
      #=> false
  """
  @spec implemented?(module(), module()) :: boolean()
  def implemented?(protocol, for_type) do
    case get_implementation(protocol, for_type) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Verifies that a protocol implementation is complete.

  Checks that all required callbacks are implemented.

  ## Examples

      Registry.verify(FnTypes.Protocols.Recoverable, Postgrex.Error)
      #=> :ok

      Registry.verify(FnTypes.Protocols.Recoverable, IncompleteImpl)
      #=> {:error, [:missing_callback, :strategy]}
  """
  @spec verify(module(), module()) :: :ok | {:error, [atom()]}
  def verify(protocol, for_type) do
    case get_implementation(protocol, for_type) do
      {:ok, impl_module} ->
        required = get_required_callbacks(protocol)
        implemented = get_implemented_callbacks(impl_module)
        missing = required -- implemented

        if Enum.empty?(missing) do
          :ok
        else
          {:error, missing}
        end

      {:error, :not_found} ->
        {:error, [:not_implemented]}
    end
  end

  @doc """
  Verifies all implementations for a protocol.

  ## Examples

      Registry.verify_protocol(FnTypes.Protocols.Recoverable)
      #=> :ok | {:error, [{Struct, [:missing_callback]}]}
  """
  @spec verify_protocol(module()) :: :ok | {:error, [{module(), [atom()]}]}
  def verify_protocol(protocol) do
    errors =
      protocol
      |> list_implementations()
      |> Enum.map(fn {for_type, _impl} -> {for_type, verify(protocol, for_type)} end)
      |> Enum.filter(fn {_type, result} -> result != :ok end)
      |> Enum.map(fn {type, {:error, missing}} -> {type, missing} end)

    if Enum.empty?(errors), do: :ok, else: {:error, errors}
  end

  @doc """
  Verifies all known protocols.

  ## Examples

      Registry.verify_all()
      #=> :ok | {:error, %{Recoverable => [{Struct, [:callback]}]}}
  """
  @spec verify_all() :: :ok | {:error, map()}
  def verify_all do
    errors =
      list_protocols()
      |> Enum.map(fn protocol -> {protocol, verify_protocol(protocol)} end)
      |> Enum.filter(fn {_protocol, result} -> result != :ok end)
      |> Enum.into(%{}, fn {protocol, {:error, errors}} -> {protocol, errors} end)

    if map_size(errors) == 0, do: :ok, else: {:error, errors}
  end

  @doc """
  Returns a summary of all protocols and their implementations.

  ## Examples

      Registry.summary()
      #=> %{
      #     FnTypes.Protocols.Recoverable => %{
      #       implementations: 12,
      #       types: [Postgrex.Error, Ecto.Changeset, ...],
      #       has_any: true,
      #       fallback_to_any: true
      #     },
      #     ...
      #   }
  """
  @spec summary() :: map()
  def summary do
    list_protocols()
    |> Enum.into(%{}, fn protocol ->
      impls = list_implementations(protocol)
      types = Enum.map(impls, &elem(&1, 0))

      {protocol,
       %{
         implementations: length(impls),
         types: types,
         has_any: Any in types,
         fallback_to_any: fallback_to_any?(protocol),
         callbacks: get_required_callbacks(protocol)
       }}
    end)
  end

  @doc """
  Returns protocol information for a specific protocol.

  ## Examples

      Registry.info(FnTypes.Protocols.Recoverable)
      #=> %{
      #     name: FnTypes.Protocols.Recoverable,
      #     callbacks: [:recoverable?, :strategy, :retry_delay, ...],
      #     implementations: [...],
      #     fallback_to_any: true
      #   }
  """
  @spec info(module()) :: map() | nil
  def info(protocol) do
    if protocol_module?(protocol) do
      impls = list_implementations(protocol)

      %{
        name: protocol,
        callbacks: get_required_callbacks(protocol),
        optional_callbacks: get_optional_callbacks(protocol),
        implementations: impls,
        implementation_count: length(impls),
        fallback_to_any: fallback_to_any?(protocol),
        consolidated: consolidated?(protocol)
      }
    else
      nil
    end
  end

  @doc """
  Generates documentation for a protocol and its implementations.

  Returns markdown-formatted documentation.

  ## Examples

      Registry.docs(FnTypes.Protocols.Recoverable)
      #=> "# Recoverable Protocol\\n\\n..."
  """
  @spec docs(module()) :: String.t()
  def docs(protocol) do
    case info(protocol) do
      nil ->
        "Protocol #{inspect(protocol)} not found"

      info ->
        """
        # #{inspect(info.name)}

        ## Callbacks

        #{format_callbacks(info.callbacks, info.optional_callbacks)}

        ## Implementations (#{info.implementation_count})

        #{format_implementations(info.implementations)}

        ## Settings

        - Fallback to Any: #{info.fallback_to_any}
        - Consolidated: #{info.consolidated}
        """
    end
  end

  @doc """
  Registers additional protocols to be tracked.

  This is useful for adding protocols at runtime.

  ## Examples

      Registry.register_protocol(MyApp.Protocols.CustomProtocol)
  """
  @spec register_protocol(module()) :: :ok
  def register_protocol(protocol) when is_atom(protocol) do
    current = Application.get_env(:fn_types, __MODULE__, [])[:protocols] || @default_protocols
    updated = Enum.uniq([protocol | current])
    Application.put_env(:fn_types, __MODULE__, protocols: updated)
    :ok
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp known_protocols do
    Application.get_env(:fn_types, __MODULE__, [])[:protocols] || @default_protocols
  end

  defp protocol_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__protocol__, 1)
  end

  defp get_consolidated_impls(protocol) do
    try do
      impls = protocol.__protocol__(:impls)

      case impls do
        {:consolidated, types} ->
          impl_modules =
            Enum.map(types, fn type ->
              impl_module = Module.concat([protocol, type])
              {type, impl_module}
            end)

          {:ok, impl_modules}

        :not_consolidated ->
          :error
      end
    rescue
      _ -> :error
    end
  end

  defp discover_implementations(protocol) do
    # Common types that might have implementations
    common_types = [
      Any,
      Postgrex.Error,
      Ecto.Changeset,
      Ecto.NoResultsError,
      Ecto.StaleEntryError,
      Mint.TransportError,
      Mint.HTTPError,
      DBConnection.ConnectionError,
      FnTypes.Error
    ]

    common_types
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.filter(fn type ->
      impl_module = Module.concat([protocol, type])
      Code.ensure_loaded?(impl_module)
    end)
    |> Enum.map(fn type ->
      {type, Module.concat([protocol, type])}
    end)
  end

  defp get_required_callbacks(protocol) do
    if function_exported?(protocol, :__protocol__, 1) do
      protocol.__protocol__(:functions)
      |> Keyword.keys()
    else
      []
    end
  rescue
    _ -> []
  end

  defp get_optional_callbacks(_protocol) do
    # Protocols don't have optional callbacks in Elixir
    []
  end

  defp get_implemented_callbacks(impl_module) do
    if Code.ensure_loaded?(impl_module) do
      impl_module.__info__(:functions)
      |> Keyword.keys()
    else
      []
    end
  rescue
    _ -> []
  end

  defp fallback_to_any?(protocol) do
    if function_exported?(protocol, :__protocol__, 1) do
      case protocol.__protocol__(:impls) do
        {:consolidated, types} ->
          Any in types

        :not_consolidated ->
          any_impl = Module.concat([protocol, Any])
          Code.ensure_loaded?(any_impl)
      end
    else
      false
    end
  rescue
    _ -> false
  end

  defp consolidated?(protocol) do
    if function_exported?(protocol, :__protocol__, 1) do
      case protocol.__protocol__(:impls) do
        {:consolidated, _} -> true
        _ -> false
      end
    else
      false
    end
  rescue
    _ -> false
  end

  defp format_callbacks(callbacks, optional) do
    callbacks
    |> Enum.map(fn callback ->
      optional_mark = if callback in optional, do: " (optional)", else: ""
      "- `#{callback}/1`#{optional_mark}"
    end)
    |> Enum.join("\n")
  end

  defp format_implementations(implementations) do
    implementations
    |> Enum.map(fn {type, impl} ->
      "- `#{inspect(type)}` -> `#{inspect(impl)}`"
    end)
    |> Enum.join("\n")
  end
end
