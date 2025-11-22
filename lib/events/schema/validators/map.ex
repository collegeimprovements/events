defmodule Events.Schema.Validators.Map do
  @moduledoc """
  Map-specific validations for enhanced schema fields.

  Provides key and size validations for map fields.
  """

  @doc """
  Apply all map validations to a changeset.
  """
  def validate(changeset, field_name, opts) do
    changeset
    |> validate_keys(field_name, opts)
    |> validate_size(field_name, opts)
  end

  # Key validations

  defp validate_keys(changeset, field_name, opts) do
    case Ecto.Changeset.get_change(changeset, field_name) do
      nil ->
        changeset

      map when is_map(map) ->
        changeset
        |> validate_required_keys(field_name, map, opts)
        |> validate_forbidden_keys(field_name, map, opts)

      _ ->
        changeset
    end
  end

  defp validate_required_keys(changeset, field_name, map, opts) do
    case opts[:required_keys] do
      nil ->
        changeset

      required_keys ->
        missing = Enum.filter(required_keys, fn key -> not Map.has_key?(map, key) end)

        if missing != [] do
          Ecto.Changeset.add_error(
            changeset,
            field_name,
            "missing required keys: #{inspect(missing)}"
          )
        else
          changeset
        end
    end
  end

  defp validate_forbidden_keys(changeset, field_name, map, opts) do
    case opts[:forbidden_keys] do
      nil ->
        changeset

      forbidden_keys ->
        present = Enum.filter(forbidden_keys, fn key -> Map.has_key?(map, key) end)

        if present != [] do
          Ecto.Changeset.add_error(
            changeset,
            field_name,
            "contains forbidden keys: #{inspect(present)}"
          )
        else
          changeset
        end
    end
  end

  # Size validation

  defp validate_size(changeset, field_name, opts) do
    case Ecto.Changeset.get_change(changeset, field_name) do
      nil ->
        changeset

      map when is_map(map) ->
        size = map_size(map)
        min = opts[:min_keys]
        max = opts[:max_keys]

        cond do
          min && size < min ->
            Ecto.Changeset.add_error(changeset, field_name, "must have at least #{min} keys")

          max && size > max ->
            Ecto.Changeset.add_error(changeset, field_name, "must have at most #{max} keys")

          true ->
            changeset
        end

      _ ->
        changeset
    end
  end
end
