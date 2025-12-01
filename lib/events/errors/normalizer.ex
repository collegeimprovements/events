defmodule Events.Errors.Normalizer do
  @moduledoc """
  Public API for normalizing errors from various sources.

  This module provides a unified interface for converting errors from different
  sources (Ecto, HTTP, AWS, POSIX, etc.) into the standard `Events.Error` struct.

  ## Protocol-Based Normalization

  This module delegates to the `Events.Normalizable` protocol, which provides
  type-based dispatch for error normalization. Any type can be made normalizable
  by implementing the protocol.

  ## Supported Sources (via Protocol Implementations)

  - **Ecto** - Changesets, NoResultsError, StaleEntryError, ConstraintError
  - **Postgrex** - Database errors with PostgreSQL error codes
  - **DBConnection** - Connection pool errors
  - **Mint** - HTTP transport and protocol errors
  - **HTTP** - Status codes via `Events.HttpError` wrapper
  - **POSIX** - File system errors via `Events.PosixError` wrapper
  - **Exceptions** - Any Elixir exception (via Any fallback)
  - **Result tuples** - `{:error, term()}`
  - **Custom types** - Any struct implementing `Events.Normalizable`

  ## Usage

      # Normalize any error (uses protocol dispatch)
      Normalizer.normalize({:error, :not_found})
      Normalizer.normalize(%Ecto.Changeset{valid?: false})
      Normalizer.normalize(%Mint.TransportError{reason: :timeout})

      # With context
      Normalizer.normalize(error, context: %{user_id: 123})

      # Normalize result tuples
      {:ok, user} |> Normalizer.normalize_result()  #=> {:ok, user}
      {:error, :not_found} |> Normalizer.normalize_result()  #=> {:error, %Error{}}

      # In pipelines
      User.create(attrs)
      |> Normalizer.normalize_pipe()
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, %Error{} = error} -> {:error, error}
      end

      # Wrap function calls
      Normalizer.wrap(fn -> risky_operation() end)
      #=> {:ok, result} | {:error, %Error{}}

  ## Extending with Custom Types

  Implement the `Events.Normalizable` protocol for your custom error types:

      defimpl Events.Normalizable, for: MyApp.PaymentError do
        def normalize(%{code: code}, opts) do
          Events.Error.new(:unprocessable, code,
            message: "Payment failed",
            context: Keyword.get(opts, :context, %{})
          )
        end
      end

  Or use `@derive`:

      defmodule MyApp.CustomError do
        @derive {Events.Normalizable, type: :business, code: :custom_error}
        defstruct [:message, :details]
      end
  """

  use Events.Decorator

  alias Events.Error

  @type normalizable :: term()

  @doc """
  Normalizes an error from any source into a standard Error struct.

  Uses the `Events.Normalizable` protocol for type-based dispatch.

  ## Options

  - `:context` - Additional context to attach to the error
  - `:stacktrace` - Stacktrace to attach (for exceptions)
  - `:step` - Pipeline step where the error occurred
  - `:message` - Override the default message

  ## Examples

      iex> Normalizer.normalize({:error, :not_found})
      %Error{type: :not_found, code: :not_found}

      iex> Normalizer.normalize(:timeout)
      %Error{type: :timeout, code: :timeout}

      iex> Normalizer.normalize(%Ecto.Changeset{valid?: false})
      %Error{type: :validation, code: :changeset_invalid}
  """
  @spec normalize(normalizable(), keyword()) :: Error.t()
  @decorate log_call(level: :debug, label: "Error normalization")
  def normalize(error, opts \\ [])

  # Unwrap result tuples
  def normalize({:error, reason}, opts) do
    normalize(reason, opts)
  end

  # Delegate to protocol
  def normalize(error, opts) do
    Events.Normalizable.normalize(error, opts)
  end

  @doc """
  Normalizes a result tuple, converting errors to Error structs.

  Passes through `{:ok, value}` tuples unchanged, normalizes `{:error, reason}`.

  ## Examples

      iex> Normalizer.normalize_result({:ok, %User{}})
      {:ok, %User{}}

      iex> Normalizer.normalize_result({:error, :not_found})
      {:error, %Error{type: :not_found, code: :not_found}}
  """
  @spec normalize_result({:ok, term()} | {:error, term()}, keyword()) ::
          {:ok, term()} | {:error, Error.t()}
  def normalize_result(result, opts \\ [])

  def normalize_result({:ok, value}, _opts), do: {:ok, value}

  def normalize_result({:error, reason}, opts) do
    {:error, normalize(reason, opts)}
  end

  def normalize_result(other, _opts) do
    {:error, normalize(other, message: "Expected {:ok, value} or {:error, reason} tuple")}
  end

  @doc """
  Normalizes errors in a pipeline.

  Pass through success values unchanged, normalize errors.

  ## Examples

      User.create(attrs)
      |> Normalizer.normalize_pipe()
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, %Error{} = error} -> {:error, error}
      end
  """
  @spec normalize_pipe({:ok, term()} | {:error, term()} | term(), keyword()) ::
          {:ok, term()} | {:error, Error.t()} | term()
  def normalize_pipe(value, opts \\ [])

  def normalize_pipe({:ok, _} = ok, _opts), do: ok
  def normalize_pipe({:error, reason}, opts), do: {:error, normalize(reason, opts)}
  def normalize_pipe(other, _opts), do: other

  @doc """
  Wraps a function call and normalizes any errors.

  Catches exceptions, exits, and throws, normalizing them all to Error structs.

  ## Examples

      Normalizer.wrap(fn -> risky_operation() end)
      #=> {:ok, result} | {:error, %Error{}}

      Normalizer.wrap(fn -> raise "boom" end)
      #=> {:error, %Error{type: :internal, code: :exception}}
  """
  @spec wrap((-> term()), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def wrap(fun, opts \\ []) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    exception ->
      error =
        Events.Normalizable.normalize(exception, Keyword.put(opts, :stacktrace, __STACKTRACE__))

      {:error, error}
  catch
    :exit, reason ->
      error = Error.new(:internal, :exit, message: "Process exited", details: %{reason: reason})
      {:error, error}

    :throw, value ->
      error = Error.new(:internal, :throw, message: "Value thrown", details: %{value: value})
      {:error, error}
  end
end
