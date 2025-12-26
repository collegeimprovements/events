defmodule FnTypes.Config.Validator do
  @moduledoc """
  Generic configuration validation framework.

  Provides a framework for validating service configurations at startup.
  Services can return structured validation results that are automatically
  categorized for display.

  ## Validation Results

  Validators return one of:
  - `{:ok, metadata}` - Configuration is valid with metadata
  - `{:error, reason}` - Configuration is invalid with reason
  - `{:warning, reason, metadata}` - Configuration has warnings but is usable
  - `{:disabled, reason}` - Service is intentionally disabled

  ## Usage

      defmodule MyApp.ConfigValidator do
        use FnTypes.Config.Validator

        validators do
          service :database,
            validator: &__MODULE__.validate_database/0,
            critical: true,
            description: "PostgreSQL connection"

          service :cache,
            validator: &__MODULE__.validate_cache/0,
            critical: false,
            description: "Cache adapter"
        end

        def validate_database do
          {:ok, %{host: "localhost", pool_size: 10}}
        end

        def validate_cache do
          {:warning, "Using in-memory cache", %{adapter: :local}}
        end
      end

      # Then use:
      MyApp.ConfigValidator.validate_all()
      #=> %{ok: [...], warnings: [...], errors: [...], disabled: [...]}

  ## Manual Usage (without DSL)

      alias FnTypes.Config.Validator

      validators = [
        %{service: :database, validator: &validate_db/0, critical: true, description: "DB"},
        %{service: :cache, validator: &validate_cache/0, critical: false, description: "Cache"}
      ]

      Validator.run_all(validators)
      Validator.run_critical(validators)
      Validator.run_one(:database, validators)
  """

  @type validation_result ::
          {:ok, map()}
          | {:error, String.t()}
          | {:warning, String.t(), map()}
          | {:disabled, String.t()}

  @type validator_spec :: %{
          service: atom(),
          validator: (-> validation_result()),
          critical: boolean(),
          description: String.t()
        }

  @type validation_output :: %{
          service: atom(),
          status: :ok | :warning | :error | :disabled,
          critical: boolean(),
          description: String.t(),
          metadata: map(),
          reason: String.t() | nil
        }

  @type categorized_results :: %{
          ok: [validation_output()],
          warnings: [validation_output()],
          errors: [validation_output()],
          disabled: [validation_output()]
        }

  # ============================================
  # DSL for Defining Validators
  # ============================================

  @doc """
  Uses the validator DSL in a module.

  Provides the `validators/1` macro and defines `validate_all/0`,
  `validate_critical/0`, and `validate_service/1` functions.

  ## Example

      defmodule MyApp.ConfigValidator do
        use FnTypes.Config.Validator

        validators do
          service :database,
            validator: &__MODULE__.validate_database/0,
            critical: true,
            description: "PostgreSQL"
        end

        def validate_database, do: {:ok, %{}}
      end
  """
  defmacro __using__(_opts) do
    quote do
      import FnTypes.Config.Validator, only: [validators: 1, service: 2]

      Module.register_attribute(__MODULE__, :validator_specs, accumulate: true)

      @before_compile FnTypes.Config.Validator
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    validators = Module.get_attribute(env.module, :validator_specs) |> Enum.reverse()

    quote do
      @validators unquote(Macro.escape(validators))

      @doc "Returns all registered validators."
      def __validators__, do: @validators

      @doc "Validates all service configurations."
      def validate_all do
        FnTypes.Config.Validator.run_all(@validators)
      end

      @doc "Validates only critical services."
      def validate_critical do
        FnTypes.Config.Validator.run_critical(@validators)
      end

      @doc "Validates a specific service."
      def validate_service(service_name) do
        FnTypes.Config.Validator.run_one(service_name, @validators)
      end
    end
  end

  @doc """
  Defines the validators block.
  """
  defmacro validators(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a service validator.

  ## Options

  - `:validator` - Function that returns a validation result (required)
  - `:critical` - Whether the service is critical (default: false)
  - `:description` - Human-readable description
  """
  defmacro service(name, opts) do
    description = Keyword.get(opts, :description) || quote(do: to_string(unquote(name)))

    quote do
      @validator_specs %{
        service: unquote(name),
        validator: unquote(opts[:validator]),
        critical: unquote(Keyword.get(opts, :critical, false)),
        description: unquote(description)
      }
    end
  end

  # ============================================
  # Public API (Functional)
  # ============================================

  @doc """
  Runs all validators and categorizes results.

  ## Examples

      Validator.run_all(validators)
      #=> %{
      #     ok: [%{service: :database, ...}],
      #     warnings: [],
      #     errors: [],
      #     disabled: []
      #   }
  """
  @spec run_all([validator_spec()]) :: categorized_results()
  def run_all(validators) do
    validators
    |> Enum.map(&run_validator/1)
    |> categorize_results()
  end

  @doc """
  Runs only critical validators and fails fast.

  Returns `{:ok, results}` if all critical services are valid.
  Returns `{:error, errors}` if any critical service has errors.

  ## Examples

      Validator.run_critical(validators)
      #=> {:ok, [...]}

      Validator.run_critical(validators)
      #=> {:error, [{:database, "DATABASE_URL not set"}]}
  """
  @spec run_critical([validator_spec()]) :: {:ok, [validation_output()]} | {:error, [{atom(), String.t()}]}
  def run_critical(validators) do
    critical_validators = Enum.filter(validators, & &1.critical)

    results = Enum.map(critical_validators, &run_validator/1)

    errors =
      results
      |> Enum.filter(&(&1.status == :error))
      |> Enum.map(&{&1.service, &1.reason})

    case errors do
      [] -> {:ok, results}
      errors -> {:error, errors}
    end
  end

  @doc """
  Runs a single validator by service name.

  ## Examples

      Validator.run_one(:database, validators)
      #=> {:ok, %{url: "...", pool_size: 10}}

      Validator.run_one(:unknown, validators)
      #=> {:error, "Unknown service: unknown"}
  """
  @spec run_one(atom(), [validator_spec()]) :: validation_result()
  def run_one(service_name, validators) do
    validators
    |> Enum.find(&(&1.service == service_name))
    |> case do
      nil -> {:error, "Unknown service: #{service_name}"}
      validator_spec -> validator_spec.validator.()
    end
  end

  # ============================================
  # Utility Functions
  # ============================================

  @doc """
  Masks sensitive information in a URL.

  Replaces passwords in URLs with asterisks for safe logging.

  ## Examples

      Validator.mask_url("postgres://user:secret@host/db")
      #=> "postgres://user:********@host/db"

      Validator.mask_url("https://user@host.com")
      #=> "https://user@host.com"
  """
  @spec mask_url(String.t() | nil) :: String.t() | nil
  def mask_url(nil), do: nil

  def mask_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> mask_userinfo()
    |> URI.to_string()
  rescue
    _ -> url
  end

  @doc """
  Masks a sensitive string, showing only first/last N characters.

  ## Examples

      Validator.mask_string("sk_test_abc123xyz789", show: 4)
      #=> "sk_t...9789"

      Validator.mask_string("short")
      #=> "****"
  """
  @spec mask_string(String.t() | nil, keyword()) :: String.t() | nil
  def mask_string(string, opts \\ [])
  def mask_string(nil, _opts), do: nil

  def mask_string(string, opts) when is_binary(string) do
    show = Keyword.get(opts, :show, 4)

    if String.length(string) <= show * 2 do
      String.duplicate("*", String.length(string))
    else
      prefix = String.slice(string, 0, show)
      suffix = String.slice(string, -show, show)
      "#{prefix}...#{suffix}"
    end
  end

  @doc """
  Creates a validator result combining multiple checks.

  Runs checks in sequence and returns the first failure,
  or `{:ok, metadata}` if all pass.

  ## Examples

      with_checks([
        fn -> check_env_var("DATABASE_URL") end,
        fn -> check_port_valid(config.port) end,
        fn -> check_pool_size(config.pool_size) end
      ], %{url: "...", port: 5432})
      #=> {:ok, %{url: "...", port: 5432}}

      with_checks([
        fn -> {:error, "DATABASE_URL not set"} end
      ], %{})
      #=> {:error, "DATABASE_URL not set"}
  """
  @spec with_checks([(-> :ok | {:error, String.t()})], map()) :: validation_result()
  def with_checks(checks, metadata) do
    Enum.reduce_while(checks, {:ok, metadata}, fn check, _acc ->
      case check.() do
        :ok -> {:cont, {:ok, metadata}}
        {:ok, _} -> {:cont, {:ok, metadata}}
        {:error, reason} -> {:halt, {:error, reason}}
        {:warning, reason, extra} -> {:halt, {:warning, reason, Map.merge(metadata, extra)}}
      end
    end)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp run_validator(%{service: service, validator: validator_fn, critical: critical} = spec) do
    case validator_fn.() do
      {:ok, metadata} ->
        %{
          service: service,
          status: :ok,
          critical: critical,
          description: spec.description,
          metadata: metadata,
          reason: nil
        }

      {:warning, reason, metadata} ->
        %{
          service: service,
          status: :warning,
          critical: critical,
          description: spec.description,
          metadata: metadata,
          reason: reason
        }

      {:error, reason} ->
        %{
          service: service,
          status: :error,
          critical: critical,
          description: spec.description,
          metadata: %{},
          reason: reason
        }

      {:disabled, reason} ->
        %{
          service: service,
          status: :disabled,
          critical: critical,
          description: spec.description,
          metadata: %{},
          reason: reason
        }
    end
  end

  defp categorize_results(results) do
    Enum.reduce(results, %{ok: [], warnings: [], errors: [], disabled: []}, fn result, acc ->
      case result.status do
        :ok -> Map.update!(acc, :ok, &[result | &1])
        :warning -> Map.update!(acc, :warnings, &[result | &1])
        :error -> Map.update!(acc, :errors, &[result | &1])
        :disabled -> Map.update!(acc, :disabled, &[result | &1])
      end
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp mask_userinfo(%URI{userinfo: nil} = uri), do: uri

  defp mask_userinfo(%URI{userinfo: userinfo} = uri) do
    masked =
      case String.split(userinfo, ":", parts: 2) do
        [user] -> user
        [user, _password] -> "#{user}:********"
      end

    Map.put(uri, :userinfo, masked)
  end
end
