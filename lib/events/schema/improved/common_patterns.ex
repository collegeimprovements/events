defmodule Events.Schema.Improved.CommonPatterns do
  @moduledoc """
  Common patterns extracted from validation modules.

  This module consolidates duplicate code patterns found throughout
  the Events.Schema validation system.
  """

  @doc """
  Generic option handler with pattern matching.

  Handles nil, tuple with options, and plain values uniformly.
  """
  def handle_option(nil, _handler), do: nil

  def handle_option({value, opts}, handler) when is_list(opts) do
    handler.(value, opts)
  end

  def handle_option(value, handler) do
    handler.(value, [])
  end

  @doc """
  Apply validation if option exists.

  Reduces repetitive nil checking.
  """
  defmacro apply_if_present(changeset, opts, key, validation) do
    quote do
      case unquote(opts)[unquote(key)] do
        nil -> unquote(changeset)
        value -> unquote(validation).(unquote(changeset), value)
      end
    end
  end

  @doc """
  Build validation options from a specification.

  Reduces duplicate option building code.
  """
  def build_options(opts, spec) do
    Enum.reduce(spec, [], fn {source, target, transform}, acc ->
      case opts[source] do
        nil -> acc
        value -> Keyword.put(acc, target, transform.(value))
      end
    end)
  end

  @doc """
  Validation result handler with comprehensive pattern matching.
  """
  def handle_result(result, field) do
    case result do
      :ok -> []
      {:ok, _} -> []
      :error -> [{field, "is invalid"}]
      {:error, msg} when is_binary(msg) -> [{field, msg}]
      {:error, msgs} when is_list(msgs) -> Enum.map(msgs, &{field, &1})
      true -> []
      false -> [{field, "is invalid"}]
      nil -> []
      errors when is_list(errors) -> errors
    end
  end

  @doc """
  Extract value and message from various option formats.
  """
  def extract_value_and_options(nil), do: {nil, []}
  def extract_value_and_options({value, opts}) when is_list(opts), do: {value, opts}
  def extract_value_and_options({value, msg}) when is_binary(msg), do: {value, [message: msg]}
  def extract_value_and_options(value), do: {value, []}

  @doc """
  Compose multiple validators into a single function.
  """
  def compose(validators) when is_list(validators) do
    fn changeset, field, opts ->
      Enum.reduce(validators, changeset, fn validator, acc ->
        validator.(acc, field, opts)
      end)
    end
  end

  @doc """
  Conditional application with guards.
  """
  def apply_when(changeset, condition, action) when condition == true do
    action.(changeset)
  end

  def apply_when(changeset, condition, action) when is_function(condition, 0) do
    if condition.() do
      action.(changeset)
    else
      changeset
    end
  end

  def apply_when(changeset, condition, action) when is_function(condition, 1) do
    if condition.(changeset) do
      action.(changeset)
    else
      changeset
    end
  end

  def apply_when(changeset, _, _), do: changeset

  @doc """
  Pipeline helper for cleaner validation chains.
  """
  defmacro pipe_validations(changeset, validations) do
    quote do
      Enum.reduce(unquote(validations), unquote(changeset), fn {validator, args}, acc ->
        apply(validator, [acc | args])
      end)
    end
  end

  @doc """
  Extract and validate options with type checking.
  """
  def get_typed_option(opts, key, type_check) when is_function(type_check) do
    case opts[key] do
      nil ->
        {:error, :not_found}

      value ->
        if type_check.(value) do
          {:ok, value}
        else
          {:error, {:invalid_type, value}}
        end
    end
  end

  @doc """
  Merge validation options with defaults.
  """
  def merge_validation_opts(defaults, custom_opts, valid_keys) do
    custom_opts
    |> Keyword.take(valid_keys)
    |> then(&Keyword.merge(defaults, &1))
  end

  @doc """
  Transform option keys with a mapping.
  """
  def transform_keys(opts, mapping) do
    Enum.reduce(mapping, [], fn {from, to}, acc ->
      case opts[from] do
        nil -> acc
        value -> Keyword.put(acc, to, value)
      end
    end)
  end

  @doc """
  Apply validation with automatic message extraction.
  """
  def validate_with_message(changeset, field, opts, key, validator) do
    {value, message} = extract_value_and_message(opts[key])

    if value do
      validator.(changeset, field, value, message: message)
    else
      changeset
    end
  end

  defp extract_value_and_message(nil), do: {nil, nil}
  defp extract_value_and_message({value, [message: msg]}), do: {value, msg}
  defp extract_value_and_message({value, _}), do: {value, nil}
  defp extract_value_and_message(value), do: {value, nil}
end
