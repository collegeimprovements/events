defmodule Events.Errors.Normalizer do
  @moduledoc """
  Public API for normalizing errors from various sources.

  This module provides a unified interface for converting errors from different
  sources (Ecto, HTTP, AWS, POSIX, etc.) into the standard `Events.Errors.Error` struct.

  ## Supported Sources

  - **Ecto** - Changesets, queries, constraints
  - **HTTP** - Status codes, Req/Tesla/HTTPoison errors
  - **AWS** - ExAws service errors
  - **POSIX** - File system errors
  - **Stripe** - Payment errors
  - **GraphQL** - Absinthe errors
  - **Business** - Domain-specific errors
  - **Exceptions** - Elixir exceptions
  - **Result tuples** - `{:error, term()}`

  ## Usage

      # Normalize any error
      Normalizer.normalize({:error, :not_found})
      Normalizer.normalize(%Ecto.Changeset{valid?: false})
      Normalizer.normalize(%HTTPoison.Error{})

      # With metadata
      Normalizer.normalize({:error, :timeout}, metadata: %{request_id: "123"})

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
  """

  use Events.Decorator

  alias Events.Errors.Error
  alias Events.Errors.Mappers

  @type normalizable ::
          {:error, term()}
          | Ecto.Changeset.t()
          | Exception.t()
          | Error.t()
          | atom()
          | String.t()

  @doc """
  Normalizes an error from any source into a standard Error struct.

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

  # Already normalized
  def normalize(%Error{} = error, opts) do
    maybe_add_metadata(error, opts)
  end

  # Result tuple
  def normalize({:error, reason}, opts) do
    normalize(reason, opts)
  end

  # Ecto changeset
  def normalize(%Ecto.Changeset{} = changeset, opts) do
    changeset
    |> Mappers.Ecto.normalize()
    |> maybe_add_metadata(opts)
  end

  # Exceptions
  def normalize(%{__exception__: true} = exception, opts) do
    exception
    |> Mappers.Exception.normalize(Keyword.get(opts, :stacktrace))
    |> maybe_add_metadata(opts)
  end

  # POSIX errors
  def normalize(posix, opts)
      when posix in [:enoent, :eacces, :eisdir, :enotdir, :eexist, :enospc] do
    posix
    |> Mappers.Posix.normalize()
    |> maybe_add_metadata(opts)
  end

  # Simple atoms
  def normalize(atom, opts) when is_atom(atom) do
    type = infer_type(atom)

    Error.new(type, atom)
    |> maybe_add_metadata(opts)
  end

  # String messages
  def normalize(message, opts) when is_binary(message) do
    Error.new(:unknown, :error, message: message)
    |> maybe_add_metadata(opts)
  end

  # Fallback
  def normalize(unknown, opts) do
    Error.new(:unknown, :error,
      message: "Unknown error",
      details: %{original: Kernel.inspect(unknown)}
    )
    |> maybe_add_metadata(opts)
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
      error = Mappers.Exception.normalize(exception, __STACKTRACE__)
      {:error, maybe_add_metadata(error, opts)}
  catch
    :exit, reason ->
      error = Error.new(:internal, :exit, message: "Process exited", details: %{reason: reason})
      {:error, maybe_add_metadata(error, opts)}

    :throw, value ->
      error = Error.new(:internal, :throw, message: "Value thrown", details: %{value: value})
      {:error, maybe_add_metadata(error, opts)}
  end

  ## Helpers

  defp maybe_add_metadata(error, opts) do
    case Keyword.get(opts, :metadata) do
      nil -> error
      metadata -> Error.with_metadata(error, metadata)
    end
  end

  defp infer_type(:not_found), do: :not_found
  defp infer_type(:unauthorized), do: :unauthorized
  defp infer_type(:forbidden), do: :forbidden
  defp infer_type(:conflict), do: :conflict
  defp infer_type(:timeout), do: :timeout
  defp infer_type(:rate_limit), do: :rate_limit
  defp infer_type(:bad_request), do: :bad_request
  defp infer_type(:invalid), do: :validation
  defp infer_type(:validation_failed), do: :validation
  defp infer_type(_), do: :unknown
end
