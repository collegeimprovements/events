defmodule Events.Schema.Helpers.Normalizer do
  @moduledoc """
  Helper module for normalizing field values.

  Provides various normalization transformations like trim, downcase, slugify, etc.
  Supports chaining multiple normalizations together.
  """

  alias Events.Schema.Slugify

  @doc """
  Apply normalization to a string value based on options.

  Supports both single normalizations and lists of normalizations to be applied in order.
  """
  def normalize(value, opts) when is_binary(value) do
    value
    |> maybe_trim(opts)
    |> apply_normalize(opts)
  end

  def normalize(value, _opts), do: value

  # Trim by default unless explicitly disabled
  defp maybe_trim(value, opts) do
    # Skip auto-trim if normalize has its own trim handling
    # or if trim is explicitly disabled
    cond do
      # Check if opts is a keyword list and has trim: false
      is_list(opts) && Keyword.get(opts, :trim) == false ->
        value

      # If normalize option contains trim-related operations, skip auto-trim
      is_list(opts) && opts[:normalize] != nil ->
        case opts[:normalize] do
          list when is_list(list) ->
            if Enum.any?(list, &(&1 in [:trim, :squish])) do
              value
            else
              String.trim(value)
            end

          :trim ->
            value

          :squish ->
            value

          # Functions handle their own trimming
          fun when is_function(fun, 1) ->
            value

          _ ->
            String.trim(value)
        end

      true ->
        String.trim(value)
    end
  end

  # Apply normalize transformations
  defp apply_normalize(value, opts) do
    case opts[:normalize] do
      nil ->
        value

      normalizers when is_list(normalizers) ->
        # Multiple normalizations - apply in order
        Enum.reduce(normalizers, value, fn normalizer, acc ->
          apply_single(acc, normalizer)
        end)

      fun when is_function(fun, 1) ->
        # Direct function passed
        fun.(value)

      normalizer ->
        apply_single(value, normalizer)
    end
  end

  # Single normalization transformations

  defp apply_single(value, :downcase), do: String.downcase(value)
  defp apply_single(value, :upcase), do: String.upcase(value)
  defp apply_single(value, :capitalize), do: String.capitalize(value)

  defp apply_single(value, :titlecase) do
    value
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp apply_single(value, :trim), do: String.trim(value)

  defp apply_single(value, :squish) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp apply_single(value, :slugify), do: Slugify.slugify(value)

  defp apply_single(value, {:slugify, opts_or_module}) when is_list(opts_or_module) do
    Slugify.slugify(value, opts_or_module)
  end

  defp apply_single(value, {:slugify, module}) when is_atom(module) do
    if Code.ensure_loaded?(module) && function_exported?(module, :slugify, 1) do
      module.slugify(value)
    else
      # Fallback to default slugify
      Slugify.slugify(value)
    end
  end

  defp apply_single(value, {:custom, fun}) when is_function(fun, 1) do
    fun.(value)
  end

  defp apply_single(value, _), do: value
end
