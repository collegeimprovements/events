defmodule Events.Infra.Decorator.Types.PipelineResult do
  @moduledoc """
  Pipeline-compatible result wrapper with chainable helpers.

  Provides functional programming utilities for working with result types,
  similar to Rust's `Result<T, E>` or Haskell's `Either`.

  ## Usage

      alias Events.Infra.Decorator.Types.PipelineResult

      create_user(attrs)
      |> PipelineResult.and_then(&send_welcome_email/1)
      |> PipelineResult.and_then(&create_settings/1)
      |> PipelineResult.map_ok(&UserView.render/1)
      |> PipelineResult.map_error(&format_error/1)
      |> PipelineResult.unwrap()

  ## Pattern

  The PipelineResult wraps a standard `{:ok, value} | {:error, reason}` tuple,
  enabling chainable operations that short-circuit on errors.
  """

  defstruct [:value]

  @type t :: %__MODULE__{value: {:ok, any()} | {:error, any()}}

  @doc """
  Creates a new PipelineResult from a result tuple.

  ## Examples

      PipelineResult.new({:ok, user})
      PipelineResult.new({:error, :not_found})
  """
  @spec new({:ok, any()} | {:error, any()}) :: t()
  def new(value), do: %__MODULE__{value: value}

  @doc """
  Chains operations that return results.

  Only executes the function if the previous result was `{:ok, value}`.
  Errors are passed through unchanged.

  ## Examples

      PipelineResult.new({:ok, user})
      |> PipelineResult.and_then(&send_welcome_email/1)
      |> PipelineResult.and_then(&create_settings/1)
  """
  @spec and_then(t(), (any() -> {:ok, any()} | {:error, any()} | t() | any())) :: t()
  def and_then(%__MODULE__{value: {:ok, value}}, fun) do
    case fun.(value) do
      {:ok, _} = result -> new(result)
      {:error, _} = error -> new(error)
      %__MODULE__{} = wrapped -> wrapped
      other -> new({:ok, other})
    end
  end

  def and_then(%__MODULE__{value: {:error, _}} = result, _fun), do: result

  @doc """
  Maps the success value, leaving errors unchanged.

  ## Examples

      PipelineResult.new({:ok, user})
      |> PipelineResult.map_ok(&UserView.render/1)
      # => %PipelineResult{value: {:ok, rendered_user}}

      PipelineResult.new({:error, :not_found})
      |> PipelineResult.map_ok(&UserView.render/1)
      # => %PipelineResult{value: {:error, :not_found}}
  """
  @spec map_ok(t(), (any() -> any())) :: t()
  def map_ok(%__MODULE__{value: {:ok, value}}, fun) do
    new({:ok, fun.(value)})
  end

  def map_ok(%__MODULE__{} = result, _fun), do: result

  @doc """
  Maps the error value, leaving successes unchanged.

  ## Examples

      PipelineResult.new({:error, changeset})
      |> PipelineResult.map_error(&format_changeset_errors/1)
      # => %PipelineResult{value: {:error, formatted_errors}}

      PipelineResult.new({:ok, user})
      |> PipelineResult.map_error(&format_changeset_errors/1)
      # => %PipelineResult{value: {:ok, user}}
  """
  @spec map_error(t(), (any() -> any())) :: t()
  def map_error(%__MODULE__{value: {:error, reason}}, fun) do
    new({:error, fun.(reason)})
  end

  def map_error(%__MODULE__{} = result, _fun), do: result

  @doc """
  Unwraps the PipelineResult, returning the inner result tuple.

  ## Examples

      PipelineResult.new({:ok, user})
      |> PipelineResult.unwrap()
      # => {:ok, user}
  """
  @spec unwrap(t()) :: {:ok, any()} | {:error, any()}
  def unwrap(%__MODULE__{value: value}), do: value

  @doc """
  Returns true if the result is a success.

  ## Examples

      PipelineResult.new({:ok, user}) |> PipelineResult.ok?()
      # => true
  """
  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{value: {:ok, _}}), do: true
  def ok?(%__MODULE__{}), do: false

  @doc """
  Returns true if the result is an error.

  ## Examples

      PipelineResult.new({:error, reason}) |> PipelineResult.error?()
      # => true
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{value: {:error, _}}), do: true
  def error?(%__MODULE__{}), do: false

  @doc """
  Unwraps the success value, raising if it's an error.

  ## Examples

      PipelineResult.new({:ok, user}) |> PipelineResult.unwrap!()
      # => user

      PipelineResult.new({:error, reason}) |> PipelineResult.unwrap!()
      # raises RuntimeError
  """
  @spec unwrap!(t()) :: any() | no_return()
  def unwrap!(%__MODULE__{value: {:ok, value}}), do: value

  def unwrap!(%__MODULE__{value: {:error, reason}}) do
    raise "Cannot unwrap error result: #{inspect(reason)}"
  end

  @doc """
  Returns the success value or a default.

  ## Examples

      PipelineResult.new({:ok, user}) |> PipelineResult.unwrap_or(nil)
      # => user

      PipelineResult.new({:error, reason}) |> PipelineResult.unwrap_or(nil)
      # => nil
  """
  @spec unwrap_or(t(), any()) :: any()
  def unwrap_or(%__MODULE__{value: {:ok, value}}, _default), do: value
  def unwrap_or(%__MODULE__{value: {:error, _}}, default), do: default
end
