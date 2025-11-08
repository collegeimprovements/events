defmodule ConfigHelper do
  @moduledoc """
  Configuration utilities for parsing environment variables with type safety.

  Provides a clean API for fetching environment variables with automatic type conversion,
  default values, and optional error handling. Can be used both at config-time and runtime.

  ## Recommended Usage

  For maximum type safety, use the specific type functions:

      ConfigHelper.get_env_integer("PORT", 4000)
      ConfigHelper.get_env_atom("LOG_LEVEL", :debug)
      ConfigHelper.get_env_boolean("ENABLED", false)

  For simple strings or dynamic types, use the unified function:

      ConfigHelper.get_env("API_KEY", "default_key")
      ConfigHelper.get_env("PORT", 4000)  # auto-infers :integer

  ## Examples

      # In config/runtime.exs
      Code.require_file("config_helper.ex", __DIR__)

      config :events,
        port: ConfigHelper.get_env_integer("PORT", 4000),
        log_level: ConfigHelper.get_env_atom("LOG_LEVEL", :debug),
        ssl_enabled: ConfigHelper.get_env_boolean("SSL_ENABLED", false)

  """

  @truthy_values ["1", "true", "yes"]

  # ==============================================================================
  # PUBLIC API - Unified Interface
  # ==============================================================================

  @doc """
  Fetches an environment variable with automatic type inference or explicit conversion.

  Type is inferred from the default value, or can be explicitly specified.

  ## Options

    * `:default` - Default value if environment variable is not set
    * `:type` - Explicit type: `:string`, `:integer`, `:atom`, `:boolean`
    * `:raise` - Whether to raise on missing/invalid values (default: `false`)

  ## Examples

      # String (no conversion)
      ConfigHelper.get_env("API_KEY", "default")

      # Type inference
      ConfigHelper.get_env("PORT", 4000)           # infers :integer
      ConfigHelper.get_env("ENABLED", false)       # infers :boolean
      ConfigHelper.get_env("LOG_LEVEL", :debug)    # infers :atom

      # Explicit type
      ConfigHelper.get_env("PORT", 4000, type: :integer)
      ConfigHelper.get_env("PORT", default: 4000, type: :integer)

      # With raise
      ConfigHelper.get_env("SECRET", raise: true)

  """
  @spec get_env(String.t(), keyword() | any(), keyword()) :: any()
  def get_env(var_name, opts_or_default \\ [])

  # 2-arity: keyword list - get_env("PORT", default: 4000, type: :integer)
  def get_env(var_name, opts) when is_list(opts) do
    type = Keyword.get(opts, :type, :string)
    default = Keyword.get(opts, :default)
    raise_on_error = Keyword.get(opts, :raise, false)

    fetch_and_convert(var_name, type, default, raise_on_error)
  end

  # 2-arity: direct value - get_env("PORT", 4000)
  def get_env(var_name, default) when not is_list(default) do
    type = infer_type(default)
    get_env(var_name, default: default, type: type)
  end

  # 3-arity: get_env("PORT", 4000, type: :integer)
  def get_env(var_name, default, opts) when is_list(opts) and not is_list(default) do
    type = Keyword.get(opts, :type, infer_type(default))
    raise_on_error = Keyword.get(opts, :raise, false)
    get_env(var_name, default: default, type: type, raise: raise_on_error)
  end

  # ==============================================================================
  # PUBLIC API - Type-Specific Functions
  # ==============================================================================

  @doc """
  Fetches an environment variable and converts it to an integer.

  ## Options

    * `:default` - Default value (string or integer)
    * `:raise` - Raise on missing/invalid values (default: `false`)

  ## Examples

      ConfigHelper.get_env_integer("PORT", 4000)
      ConfigHelper.get_env_integer("PORT", "4000")
      ConfigHelper.get_env_integer("PORT", default: 4000)
      ConfigHelper.get_env_integer("PORT", raise: true)

  """
  @spec get_env_integer(String.t(), keyword() | integer() | String.t()) :: integer() | nil
  def get_env_integer(var_name, opts_or_default \\ [])

  def get_env_integer(var_name, opts) when is_list(opts) do
    default = Keyword.get(opts, :default)
    raise_on_error = Keyword.get(opts, :raise, false)

    var_name
    |> fetch_env_value(default)
    |> convert_to_integer(var_name, raise_on_error)
  end

  def get_env_integer(var_name, default) when is_integer(default) or is_binary(default) do
    var_name
    |> fetch_env_value(default)
    |> convert_to_integer(var_name, false)
  end

  @doc """
  Fetches an environment variable and converts it to an atom.

  ## Options

    * `:default` - Default value (string or atom)
    * `:raise` - Raise on missing values (default: `false`)

  ## Examples

      ConfigHelper.get_env_atom("LOG_LEVEL", "debug")
      ConfigHelper.get_env_atom("LOG_LEVEL", :debug)
      ConfigHelper.get_env_atom("LOG_LEVEL", default: "debug")
      ConfigHelper.get_env_atom("LOG_LEVEL", raise: true)

  """
  @spec get_env_atom(String.t(), keyword() | String.t() | atom()) :: atom() | nil
  def get_env_atom(var_name, opts_or_default \\ [])

  def get_env_atom(var_name, opts) when is_list(opts) do
    default = Keyword.get(opts, :default)
    raise_on_error = Keyword.get(opts, :raise, false)

    var_name
    |> fetch_env_value(default)
    |> convert_to_atom(var_name, raise_on_error)
  end

  def get_env_atom(var_name, default) when is_binary(default) or is_atom(default) do
    var_name
    |> fetch_env_value(default)
    |> convert_to_atom(var_name, false)
  end

  @doc """
  Fetches an environment variable and converts it to a boolean.

  Truthy values (case-insensitive, trimmed): `"1"`, `"true"`, `"yes"`, `1`, `true`

  ## Options

    * `:default` - Default boolean value (default: `false`)

  ## Examples

      ConfigHelper.get_env_boolean("ENABLED", false)
      ConfigHelper.get_env_boolean("ENABLED", true)
      ConfigHelper.get_env_boolean("ENABLED", default: false)

  """
  @spec get_env_boolean(String.t(), keyword() | boolean()) :: boolean()
  def get_env_boolean(var_name, opts_or_default \\ false)

  def get_env_boolean(var_name, opts) when is_list(opts) do
    default = Keyword.get(opts, :default, false)

    var_name
    |> fetch_env_value(default)
    |> convert_to_boolean()
  end

  def get_env_boolean(var_name, default) when is_boolean(default) do
    var_name
    |> fetch_env_value(default)
    |> convert_to_boolean()
  end

  # ==============================================================================
  # PRIVATE - Fetching and Conversion
  # ==============================================================================

  defp fetch_and_convert(var_name, type, default, raise_on_error) do
    case type do
      :string ->
        fetch_env_string(var_name, default, raise_on_error)

      :integer ->
        get_env_integer(var_name, default: default, raise: raise_on_error)

      :atom ->
        get_env_atom(var_name, default: default, raise: raise_on_error)

      :boolean ->
        if is_boolean(default) do
          get_env_boolean(var_name, default)
        else
          get_env_boolean(var_name, default: default)
        end

      other ->
        raise_invalid_type(other)
    end
  end

  defp fetch_env_string(var_name, default, raise_on_error) do
    value = System.get_env(var_name) || default

    case {value, raise_on_error} do
      {nil, true} -> raise_missing_env(var_name)
      {nil, false} -> nil
      {value, _} -> value
    end
  end

  defp fetch_env_value(var_name, default) do
    System.get_env(var_name) || default
  end

  # ==============================================================================
  # PRIVATE - Type Conversion
  # ==============================================================================

  # Convert to integer
  defp convert_to_integer(nil, var_name, true), do: raise_missing_env(var_name)
  defp convert_to_integer(nil, var_name, false), do: log_missing_env(var_name)

  defp convert_to_integer(value, _var_name, _raise) when is_integer(value), do: value

  defp convert_to_integer(value, var_name, raise_on_error) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} ->
        integer

      {_integer, _remainder} ->
        log_warning(
          "Environment variable #{var_name} has trailing non-integer characters: #{inspect(value)}"
        )

        handle_invalid_integer(var_name, value, raise_on_error)

      :error ->
        log_warning(
          "Environment variable #{var_name} cannot be parsed as integer: #{inspect(value)}"
        )

        handle_invalid_integer(var_name, value, raise_on_error)
    end
  end

  # Convert to atom
  defp convert_to_atom(nil, var_name, true), do: raise_missing_env(var_name)
  defp convert_to_atom(nil, var_name, false), do: log_missing_env(var_name)

  defp convert_to_atom(value, _var_name, _raise) when is_atom(value), do: value
  defp convert_to_atom(value, _var_name, _raise) when is_binary(value), do: String.to_atom(value)

  # Convert to boolean
  defp convert_to_boolean(value) when is_boolean(value), do: value
  defp convert_to_boolean(value) when is_atom(value), do: value == true
  defp convert_to_boolean(value) when is_integer(value), do: value == 1

  defp convert_to_boolean(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @truthy_values))
  end

  defp convert_to_boolean(_value), do: false

  # ==============================================================================
  # PRIVATE - Error Handling
  # ==============================================================================

  defp handle_invalid_integer(var_name, value, true) do
    raise ArgumentError,
          "Environment variable #{var_name} has invalid integer value: #{inspect(value)}"
  end

  defp handle_invalid_integer(_var_name, _value, false), do: nil

  defp raise_missing_env(var_name) do
    raise """
    Environment variable #{var_name} is not set.
    Configure it in mise/fnox: mise set #{var_name}=<value>
    """
  end

  defp raise_invalid_type(type) do
    raise ArgumentError,
          "Invalid type: #{inspect(type)}. Use :string, :integer, :atom, or :boolean"
  end

  defp log_missing_env(var_name) do
    log_warning("Environment variable #{var_name} is not set, using nil")
    nil
  end

  # ==============================================================================
  # PRIVATE - Utilities
  # ==============================================================================

  defp infer_type(value) when is_integer(value), do: :integer
  defp infer_type(value) when is_boolean(value), do: :boolean
  defp infer_type(value) when is_atom(value), do: :atom
  defp infer_type(value) when is_binary(value), do: :string
  defp infer_type(_value), do: :string

  defp log_warning(message) do
    if Code.ensure_loaded?(Logger) do
      require Logger
      Logger.warning(message)
    else
      IO.warn(message)
    end
  end
end
