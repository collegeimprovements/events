defmodule Events.Schema.Improved.ValidationHelpers do
  @moduledoc """
  Improved validation helpers using better pattern matching and pipelines.

  This module demonstrates cleaner code patterns that could be applied
  throughout the Events.Schema system.
  """

  import Ecto.Changeset

  @doc """
  Apply validation with improved pattern matching for tuple/value options.

  Instead of multiple case statements, use pattern matching more effectively.
  """
  def apply_validation(changeset, field, opts, key, validation_fn) do
    opts
    |> Keyword.get(key)
    |> validate_with_pattern(changeset, field, validation_fn)
  end

  # Pattern match on different option formats
  defp validate_with_pattern(nil, changeset, _field, _fn), do: changeset

  defp validate_with_pattern({value, [message: msg]}, changeset, field, validation_fn) do
    validation_fn.(changeset, field, value, message: msg)
  end

  defp validate_with_pattern({value, _opts}, changeset, field, validation_fn) do
    validation_fn.(changeset, field, value)
  end

  defp validate_with_pattern(value, changeset, field, validation_fn) do
    validation_fn.(changeset, field, value)
  end

  @doc """
  Build validation options using a cleaner pipeline approach.
  """
  def build_validation_options(opts, extractors) do
    extractors
    |> Enum.reduce([], fn {key, extractor}, acc ->
      extract_and_add(acc, opts, key, extractor)
    end)
  end

  defp extract_and_add(acc, opts, key, extractor) do
    case extractor.(opts) do
      nil -> acc
      value -> Keyword.put(acc, key, value)
    end
  end

  @doc """
  Apply multiple validations using a pipeline with guards.
  """
  defmacro validation_pipeline(changeset, field, opts, validations) do
    quote do
      Enum.reduce(unquote(validations), unquote(changeset), fn
        {condition_fn, validation_fn}, acc when is_function(condition_fn) ->
          if condition_fn.(unquote(opts)) do
            validation_fn.(acc, unquote(field), unquote(opts))
          else
            acc
          end

        validation_fn, acc when is_function(validation_fn) ->
          validation_fn.(acc, unquote(field), unquote(opts))
      end)
    end
  end

  @doc """
  Extract value with better pattern matching for tuple options.
  """
  def extract_value({value, _opts}), do: value
  def extract_value(value), do: value

  @doc """
  Extract message with pattern matching.
  """
  def extract_message({_value, opts}) when is_list(opts), do: opts[:message]
  def extract_message(_), do: nil

  @doc """
  Compose multiple validators into a single pipeline.
  """
  def compose_validators(validators) do
    fn changeset, field, opts ->
      Enum.reduce(validators, changeset, fn validator, acc ->
        validator.(acc, field, opts)
      end)
    end
  end

  @doc """
  Apply validation conditionally with pattern matching.
  """
  def apply_if(changeset, field, opts, key, validation_fn) do
    with true <- Keyword.has_key?(opts, key),
         value when not is_nil(value) <- opts[key] do
      validation_fn.(changeset, field, value, opts)
    else
      _ -> changeset
    end
  end

  @doc """
  Pattern match on validation results more elegantly.
  """
  def handle_validation_result(changeset, field, validation_fn, value) do
    case validation_fn.(value) do
      :ok ->
        changeset

      {:ok, _} ->
        changeset

      {:error, message} when is_binary(message) ->
        add_error(changeset, field, message)

      {:error, messages} when is_list(messages) ->
        Enum.reduce(messages, changeset, fn msg, acc ->
          add_error(acc, field, msg)
        end)

      false ->
        add_error(changeset, field, "is invalid")

      true ->
        changeset
    end
  end
end
