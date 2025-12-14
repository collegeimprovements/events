defmodule FnTypes.Config do
  @moduledoc """
  Type-safe environment variable configuration.

  All values are automatically trimmed. Empty strings and whitespace-only
  values are treated as unset (return nil or default).

  ## Type-Specific Getters

      alias FnTypes.Config, as: Cfg

      Cfg.string("API_KEY", "default")
      Cfg.integer("PORT", 4000)
      Cfg.boolean("DEBUG", false)
      Cfg.atom("LOG_LEVEL", :info)
      Cfg.float("RATE", 1.0)
      Cfg.list("HOSTS", ",", [])
      Cfg.url("PROXY_URL")

  ## Required Values (Bang Variants)

      Cfg.string!("DATABASE_URL")
      Cfg.integer!("PORT")
      Cfg.string!("API_KEY", message: "Set API_KEY in mise")

  ## Fallback Chains

  Try multiple env var names in order:

      # Tries AWS_REGION, then AWS_DEFAULT_REGION, then returns "us-east-1"
      Cfg.string(["AWS_REGION", "AWS_DEFAULT_REGION"], "us-east-1")

      # Required with fallback chain
      Cfg.string!(["STRIPE_API_KEY", "STRIPE_SECRET_KEY"])

  ## Priority Chains with `first_of/1`

  Compose multiple sources with explicit priority:

      # Env var > App config > Default
      Cfg.first_of([
        Cfg.boolean("S3_ENABLED"),
        Cfg.from_app(:my_app, [:services, :s3]),
        true
      ])

      # Lazy evaluation (functions only called if needed)
      Cfg.first_of([
        Cfg.string("FAST_VAR"),
        fn -> expensive_lookup() end,
        "default"
      ])

  ## Application Config

      Cfg.from_app(:my_app, :port)
      Cfg.from_app(:my_app, [:database, :pool_size])

  ## Presence Check

      Cfg.present?("DATABASE_URL")
      Cfg.present?(["AWS_KEY", "AWS_ACCESS_KEY_ID"])

  ## Boolean Parsing

  Truthy values (case-insensitive, trimmed): `"1"`, `"true"`, `"yes"`, `"y"`, `"on"`, `"✓"`, `"✅"`

  Everything else is falsy.
  """

  @truthy_values ["1", "true", "yes", "y", "on", "✓", "✅"]

  # ============================================
  # String
  # ============================================

  @doc """
  Gets a string environment variable.

  ## Examples

      FnTypes.Config.string("API_KEY")           # nil if not set
      FnTypes.Config.string("API_KEY", "key")    # "key" if not set

      # Fallback chain
      FnTypes.Config.string(["VAR1", "VAR2"], "default")
  """
  @spec string(String.t() | [String.t()], String.t() | nil) :: String.t() | nil
  def string(name, default \\ nil) do
    fetch_raw(name) || default
  end

  @doc """
  Gets a required string environment variable.

  Raises `RuntimeError` if not set or empty.

  ## Options

    * `:message` - Custom error message

  ## Examples

      FnTypes.Config.string!("DATABASE_URL")
      FnTypes.Config.string!(["VAR1", "VAR2"])
      FnTypes.Config.string!("VAR", message: "Set VAR in your environment")
  """
  @spec string!(String.t() | [String.t()], keyword()) :: String.t()
  def string!(name, opts \\ []) do
    fetch_raw(name) || raise_missing(name, opts)
  end

  # ============================================
  # Integer
  # ============================================

  @doc """
  Gets an integer environment variable.

  ## Examples

      FnTypes.Config.integer("PORT", 4000)
      FnTypes.Config.integer(["PORT", "HTTP_PORT"], 3000)
  """
  @spec integer(String.t() | [String.t()], integer() | nil) :: integer() | nil
  def integer(name, default \\ nil) do
    case fetch_raw(name) do
      nil -> default
      value -> parse_integer(value, default)
    end
  end

  @doc """
  Gets a required integer environment variable.

  Raises `RuntimeError` if not set or invalid.
  """
  @spec integer!(String.t() | [String.t()], keyword()) :: integer()
  def integer!(name, opts \\ []) do
    case fetch_raw(name) do
      nil -> raise_missing(name, opts)
      value -> parse_integer!(value, name)
    end
  end

  # ============================================
  # Boolean
  # ============================================

  @doc """
  Gets a boolean environment variable.

  Truthy values: "1", "true", "yes", "y", "on", "✓", "✅" (case-insensitive, trimmed)
  Everything else is falsy.

  ## Examples

      FnTypes.Config.boolean("DEBUG", false)
      FnTypes.Config.boolean("ENABLED")  # nil if not set
  """
  @spec boolean(String.t() | [String.t()], boolean() | nil) :: boolean() | nil
  def boolean(name, default \\ nil) do
    case fetch_raw(name) do
      nil -> default
      value -> parse_boolean(value)
    end
  end

  @doc """
  Gets a required boolean environment variable.

  Raises `RuntimeError` if not set.
  """
  @spec boolean!(String.t() | [String.t()], keyword()) :: boolean()
  def boolean!(name, opts \\ []) do
    case fetch_raw(name) do
      nil -> raise_missing(name, opts)
      value -> parse_boolean(value)
    end
  end

  # ============================================
  # Atom
  # ============================================

  @doc """
  Gets an atom environment variable.

  Converts the string value to an existing atom.

  ## Examples

      FnTypes.Config.atom("LOG_LEVEL", :info)
      FnTypes.Config.atom("CACHE_ADAPTER", :local)
  """
  @spec atom(String.t() | [String.t()], atom() | nil) :: atom() | nil
  def atom(name, default \\ nil) do
    case fetch_raw(name) do
      nil -> default
      value -> String.to_existing_atom(value)
    end
  end

  @doc """
  Gets a required atom environment variable.

  Raises `RuntimeError` if not set.
  """
  @spec atom!(String.t() | [String.t()], keyword()) :: atom()
  def atom!(name, opts \\ []) do
    case fetch_raw(name) do
      nil -> raise_missing(name, opts)
      value -> String.to_existing_atom(value)
    end
  end

  # ============================================
  # Float
  # ============================================

  @doc """
  Gets a float environment variable.

  ## Examples

      FnTypes.Config.float("RATE", 1.0)
      FnTypes.Config.float("MULTIPLIER", 0.5)
  """
  @spec float(String.t() | [String.t()], float() | nil) :: float() | nil
  def float(name, default \\ nil) do
    case fetch_raw(name) do
      nil -> default
      value -> parse_float(value, default)
    end
  end

  @doc """
  Gets a required float environment variable.

  Raises `RuntimeError` if not set or invalid.
  """
  @spec float!(String.t() | [String.t()], keyword()) :: float()
  def float!(name, opts \\ []) do
    case fetch_raw(name) do
      nil -> raise_missing(name, opts)
      value -> parse_float!(value, name)
    end
  end

  # ============================================
  # List
  # ============================================

  @doc """
  Gets a list environment variable by splitting on a delimiter.

  ## Examples

      FnTypes.Config.list("ALLOWED_HOSTS", ",", [])
      # "a,b,c" -> ["a", "b", "c"]

      FnTypes.Config.list("PATHS", ":", ["/usr/bin"])
  """
  @spec list(String.t() | [String.t()], String.t(), [String.t()]) :: [String.t()]
  def list(name, delimiter \\ ",", default \\ []) do
    case fetch_raw(name) do
      nil -> default
      value -> String.split(value, delimiter, trim: true)
    end
  end

  # ============================================
  # URL
  # ============================================

  @doc """
  Gets a URL environment variable and parses it.

  Returns a `URI` struct or nil if not set.

  ## Examples

      FnTypes.Config.url("HTTPS_PROXY")
      FnTypes.Config.url(["HTTPS_PROXY", "HTTP_PROXY"])
  """
  @spec url(String.t() | [String.t()]) :: URI.t() | nil
  def url(name) do
    case fetch_raw(name) do
      nil -> nil
      value -> URI.parse(value)
    end
  end

  @doc """
  Gets a required URL environment variable.

  Raises `RuntimeError` if not set.
  """
  @spec url!(String.t() | [String.t()], keyword()) :: URI.t()
  def url!(name, opts \\ []) do
    case fetch_raw(name) do
      nil -> raise_missing(name, opts)
      value -> URI.parse(value)
    end
  end

  # ============================================
  # Application Config Integration
  # ============================================

  @doc """
  Reads from Application config.

  ## Examples

      FnTypes.Config.from_app(:events, :port)
      FnTypes.Config.from_app(:events, [:database, :pool_size])
  """
  @spec from_app(atom(), atom() | [atom()]) :: any()
  def from_app(app, path) do
    get_app_config(app, path)
  end

  @doc """
  Returns first non-nil value from a list of sources.

  Makes the priority chain explicit and readable. Supports both values and
  zero-arity functions for lazy evaluation.

  ## Examples

      # Eager evaluation (all sources evaluated immediately)
      Cfg.first_of([
        Cfg.boolean("S3_ENABLED"),
        Cfg.from_app(:events, [:kill_switch, :s3]),
        true
      ])

      # Lazy evaluation (functions only called if needed)
      Cfg.first_of([
        fn -> Cfg.boolean("S3_ENABLED") end,
        fn -> Cfg.from_app(:events, [:kill_switch, :s3]) end,
        true
      ])

      # Mixed - useful when some sources are expensive
      Cfg.first_of([
        Cfg.string("FAST_VAR"),           # evaluated immediately
        fn -> expensive_lookup() end,      # only called if FAST_VAR not set
        "default"
      ])
  """
  @spec first_of([any() | (-> any())]) :: any()
  def first_of(sources) when is_list(sources) do
    Enum.reduce_while(sources, nil, fn
      source, nil when is_function(source, 0) ->
        case source.() do
          nil -> {:cont, nil}
          value -> {:halt, value}
        end

      nil, nil ->
        {:cont, nil}

      value, nil ->
        {:halt, value}
    end)
  end

  # ============================================
  # Presence Check
  # ============================================

  @doc """
  Checks if an environment variable is set (non-nil, non-empty).

  ## Examples

      FnTypes.Config.present?("DATABASE_URL")
      FnTypes.Config.present?(["AWS_ACCESS_KEY_ID", "AWS_KEY"])
  """
  @spec present?(String.t() | [String.t()]) :: boolean()
  def present?(names) when is_list(names) do
    Enum.any?(names, &(non_empty_env(&1) != nil))
  end

  def present?(name) when is_binary(name) do
    non_empty_env(name) != nil
  end

  # ============================================
  # Private Helpers
  # ============================================

  # Fetches raw string value from env var(s), handling both single name and fallback chains
  defp fetch_raw(names) when is_list(names) do
    Enum.find_value(names, &non_empty_env/1)
  end

  defp fetch_raw(name) when is_binary(name) do
    non_empty_env(name)
  end

  defp non_empty_env(name) do
    case System.get_env(name) do
      nil -> nil
      value ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end
    end
  end

  defp parse_boolean(value) when is_binary(value) do
    String.downcase(value) in @truthy_values
  end

  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_integer!(value, name) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise "Invalid integer value for #{format_name(name)}: #{inspect(value)}"
    end
  end

  defp parse_float(value, default) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> default
    end
  end

  defp parse_float!(value, name) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> raise "Invalid float value for #{format_name(name)}: #{inspect(value)}"
    end
  end

  defp get_app_config(app, path) when is_list(path) do
    Enum.reduce(path, Application.get_all_env(app), fn
      key, config when is_map(config) -> Map.get(config, key)
      key, config when is_list(config) -> Keyword.get(config, key)
      _key, _other -> nil
    end)
  end

  defp get_app_config(app, key) when is_atom(key) do
    Application.get_env(app, key)
  end

  defp raise_missing(name, opts) do
    message = Keyword.get(opts, :message)

    if message do
      raise message
    else
      raise "Missing required environment variable: #{format_name(name)}"
    end
  end

  defp format_name(names) when is_list(names), do: Enum.join(names, " or ")
  defp format_name(name), do: name
end
