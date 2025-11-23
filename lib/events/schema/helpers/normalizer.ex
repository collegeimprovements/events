defmodule Events.Schema.Helpers.Normalizer do
  @moduledoc """
  Helper module for normalizing field values.

  Provides various normalization transformations like trim, downcase, slugify, etc.
  Supports chaining multiple normalizations together.
  """

  alias Events.Schema.Slugify

  @doc """
  Apply normalization to a string value based on options.

  Supports:
  - `mappers:` - List of mapper functions applied left to right (recommended)
  - `normalize:` - Legacy normalization options
  - Auto-trim by default (disable with `trim: false`)

  ## Examples

      # Using mappers (recommended)
      normalize(value, mappers: [&String.trim/1, &String.downcase/1])

      # Using normalize (legacy)
      normalize(value, normalize: [:trim, :downcase])

      # Disable auto-trim
      normalize(value, trim: false)
  """
  def normalize(value, opts) when is_binary(value) do
    cond do
      # If mappers is present, use mappers (no auto-trim, mappers control everything)
      opts[:mappers] != nil ->
        apply_mappers(value, opts[:mappers])

      # Legacy normalize path with auto-trim
      true ->
        value
        |> maybe_trim(opts)
        |> apply_normalize(opts)
    end
  end

  def normalize(value, _opts), do: value

  # Apply mappers left to right
  defp apply_mappers(value, mappers) when is_list(mappers) do
    Enum.reduce(mappers, value, fn mapper, acc ->
      apply_mapper(acc, mapper)
    end)
  end

  defp apply_mappers(value, mapper) do
    apply_mapper(value, mapper)
  end

  # Apply a single mapper
  defp apply_mapper(value, fun) when is_function(fun, 1) do
    fun.(value)
  end

  defp apply_mapper(value, mapper) when is_atom(mapper) do
    # Support atom shortcuts like :trim, :downcase
    apply_single(value, mapper)
  end

  defp apply_mapper(value, {mapper, opts}) when is_atom(mapper) and is_list(opts) do
    # Support tuple format like {:slugify, uniquify: true}
    apply_single(value, {mapper, opts})
  end

  defp apply_mapper(value, _), do: value

  # Trim by default unless explicitly disabled with trim: false
  defp maybe_trim(value, opts) do
    if Keyword.get(opts, :trim, true) == false do
      value
    else
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

  defp apply_single(value, :alphanumeric_only) do
    String.replace(value, ~r/[^a-zA-Z0-9]/, "")
  end

  defp apply_single(value, :digits_only) do
    String.replace(value, ~r/[^0-9]/, "")
  end

  defp apply_single(value, _), do: value
end
