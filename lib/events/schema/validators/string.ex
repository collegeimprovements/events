defmodule Events.Schema.Validators.String do
  @moduledoc """
  String-specific validations for enhanced schema fields.

  Provides length, format, inclusion, and exclusion validations for string fields.
  """

  alias Events.Schema.Helpers.Messages
  alias Events.Schema.Types

  @doc """
  Apply all string validations to a changeset.
  """
  @spec validate(Types.changeset(), Types.field_name(), Types.opts()) :: Types.changeset()
  def validate(changeset, field_name, opts) do
    changeset
    |> apply_length_validation(field_name, opts)
    |> apply_format_validation(field_name, opts)
    |> apply_inclusion_validation(field_name, opts)
    |> apply_exclusion_validation(field_name, opts)
  end

  # Length validations

  defp apply_length_validation(changeset, field_name, opts) do
    changeset
    |> validate_min_length(field_name, opts)
    |> validate_max_length(field_name, opts)
    |> validate_exact_length(field_name, opts)
  end

  defp validate_min_length(changeset, field_name, opts) do
    case opts[:min_length] do
      nil ->
        changeset

      {min_val, inline_opts} when is_list(inline_opts) ->
        Ecto.Changeset.validate_length(changeset, field_name,
          min: min_val,
          message: inline_opts[:message]
        )

      min_val ->
        msg = Messages.get_from_opts(opts, :length)

        if msg do
          Ecto.Changeset.validate_length(changeset, field_name, min: min_val, message: msg)
        else
          Ecto.Changeset.validate_length(changeset, field_name, min: min_val)
        end
    end
  end

  defp validate_max_length(changeset, field_name, opts) do
    case opts[:max_length] do
      nil ->
        changeset

      {max_val, inline_opts} when is_list(inline_opts) ->
        Ecto.Changeset.validate_length(changeset, field_name,
          max: max_val,
          message: inline_opts[:message]
        )

      max_val ->
        msg = Messages.get_from_opts(opts, :length)

        if msg do
          Ecto.Changeset.validate_length(changeset, field_name, max: max_val, message: msg)
        else
          Ecto.Changeset.validate_length(changeset, field_name, max: max_val)
        end
    end
  end

  defp validate_exact_length(changeset, field_name, opts) do
    case opts[:length] do
      nil ->
        changeset

      {len_val, inline_opts} when is_list(inline_opts) ->
        Ecto.Changeset.validate_length(changeset, field_name,
          is: len_val,
          message: inline_opts[:message]
        )

      len_val ->
        msg = Messages.get_from_opts(opts, :length)

        if msg do
          Ecto.Changeset.validate_length(changeset, field_name, is: len_val, message: msg)
        else
          Ecto.Changeset.validate_length(changeset, field_name, is: len_val)
        end
    end
  end

  # Format validation

  defp apply_format_validation(changeset, field_name, opts) do
    case opts[:format] do
      nil ->
        changeset

      format when is_atom(format) ->
        validate_named_format(changeset, field_name, format, opts)

      {format, inline_opts} when is_atom(format) and is_list(inline_opts) ->
        validate_named_format_with_message(changeset, field_name, format, inline_opts)

      %Regex{} = regex ->
        validate_regex_format(changeset, field_name, regex, opts)

      {%Regex{} = regex, inline_opts} ->
        Ecto.Changeset.validate_format(changeset, field_name, regex, inline_opts)
    end
  end

  defp validate_named_format(changeset, field_name, format, opts) do
    regex = named_format_regex(format)
    msg = Messages.get_from_opts(opts, :format) || named_format_message(format)
    Ecto.Changeset.validate_format(changeset, field_name, regex, message: msg)
  end

  defp validate_named_format_with_message(changeset, field_name, format, inline_opts) do
    regex = named_format_regex(format)
    msg = inline_opts[:message] || named_format_message(format)
    Ecto.Changeset.validate_format(changeset, field_name, regex, message: msg)
  end

  defp validate_regex_format(changeset, field_name, regex, opts) do
    format_opts = Messages.add_to_opts([], opts, :format)
    Ecto.Changeset.validate_format(changeset, field_name, regex, format_opts)
  end

  # Inclusion/Exclusion validations

  defp apply_inclusion_validation(changeset, field_name, opts) do
    case opts[:in] do
      nil ->
        changeset

      values when is_list(values) ->
        inclusion_opts = Messages.add_to_opts([], opts, :inclusion)
        Ecto.Changeset.validate_inclusion(changeset, field_name, values, inclusion_opts)
    end
  end

  defp apply_exclusion_validation(changeset, field_name, opts) do
    case opts[:not_in] do
      nil ->
        changeset

      values when is_list(values) ->
        exclusion_opts = Messages.add_to_opts([], opts, :exclusion)
        Ecto.Changeset.validate_exclusion(changeset, field_name, values, exclusion_opts)
    end
  end

  # Named format patterns

  defp named_format_regex(:email), do: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  defp named_format_regex(:url), do: ~r/^https?:\/\//

  defp named_format_regex(:uuid),
    do: ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  defp named_format_regex(:slug), do: ~r/^[a-z0-9-]+$/
  defp named_format_regex(:hex_color), do: ~r/^#[0-9a-f]{6}$/i
  defp named_format_regex(:ip), do: ~r/^(\d{1,3}\.){3}\d{1,3}$/
  defp named_format_regex(_), do: ~r/./

  defp named_format_message(:email), do: "must be a valid email"
  defp named_format_message(:url), do: "must be a valid URL"
  defp named_format_message(:uuid), do: "must be a valid UUID"
  defp named_format_message(:slug), do: "must be a valid slug"
  defp named_format_message(:hex_color), do: "must be a valid hex color"
  defp named_format_message(:ip), do: "must be a valid IP address"
  defp named_format_message(_), do: "has invalid format"
end
