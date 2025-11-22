defmodule Events.Schema.Improved.StringValidator do
  @moduledoc """
  Improved string validator using better pattern matching and pipelines.

  This demonstrates how the string validator could be refactored for clarity.
  """

  import Ecto.Changeset
  alias Events.Schema.Helpers.Messages

  # Main validation pipeline
  def validate(changeset, field, opts) do
    changeset
    |> validate_field_length(field, opts)
    |> validate_field_format(field, opts)
    |> validate_field_inclusion(field, opts)
    |> validate_field_exclusion(field, opts)
  end

  # Length validation with better pattern matching
  defp validate_field_length(changeset, field, opts) do
    changeset
    |> apply_length_validation(field, opts, :min_length, :min)
    |> apply_length_validation(field, opts, :max_length, :max)
    |> apply_exact_length(field, opts)
  end

  # Generic length validation handler
  defp apply_length_validation(changeset, field, opts, opt_key, ecto_key) do
    case opts[opt_key] do
      nil ->
        changeset

      {value, [message: msg]} ->
        validate_length(changeset, field, [{ecto_key, value}, {:message, msg}])

      {value, _} ->
        validate_length(changeset, field, [{ecto_key, value}])

      value ->
        validate_length(changeset, field, [{ecto_key, value}])
    end
  end

  # Exact length with pattern matching
  defp apply_exact_length(changeset, field, opts) do
    case opts[:length] do
      nil ->
        changeset

      {value, [message: msg]} ->
        validate_length(changeset, field, is: value, message: msg)

      value ->
        validate_length(changeset, field, is: value)
    end
  end

  # Format validation with improved pattern matching
  defp validate_field_format(changeset, field, opts) do
    opts[:format]
    |> format_to_regex()
    |> apply_format_validation(changeset, field, opts)
  end

  # Convert format to regex using pattern matching
  defp format_to_regex(nil), do: nil
  defp format_to_regex(%Regex{} = regex), do: regex
  defp format_to_regex({%Regex{} = regex, _}), do: regex
  defp format_to_regex({atom, _}) when is_atom(atom), do: named_regex(atom)
  defp format_to_regex(atom) when is_atom(atom), do: named_regex(atom)

  # Apply format validation
  defp apply_format_validation(nil, changeset, _, _), do: changeset

  defp apply_format_validation(regex, changeset, field, opts) do
    message = extract_format_message(opts[:format]) || default_format_message(opts[:format])
    validate_format(changeset, field, regex, message: message)
  end

  # Extract message from format option
  defp extract_format_message({_, [message: msg]}), do: msg
  defp extract_format_message({_, opts}) when is_list(opts), do: opts[:message]
  defp extract_format_message(_), do: nil

  # Default messages based on format type
  defp default_format_message({atom, _}) when is_atom(atom), do: format_message(atom)
  defp default_format_message(atom) when is_atom(atom), do: format_message(atom)
  defp default_format_message(_), do: "has invalid format"

  # Named format regexes using pattern matching
  defp named_regex(format) do
    case format do
      :email -> ~r/@/
      :url -> ~r/^https?:\/\//
      :uuid -> ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      :slug -> ~r/^[a-z0-9-]+$/
      :hex_color -> ~r/^#[0-9a-f]{6}$/i
      :ip -> ~r/^(\d{1,3}\.){3}\d{1,3}$/
      _ -> ~r/./
    end
  end

  # Format messages using pattern matching
  defp format_message(format) do
    case format do
      :email -> "must be a valid email"
      :url -> "must be a valid URL"
      :uuid -> "must be a valid UUID"
      :slug -> "must be a valid slug"
      :hex_color -> "must be a valid hex color"
      :ip -> "must be a valid IP address"
      _ -> "has invalid format"
    end
  end

  # Inclusion/Exclusion with pipelines
  defp validate_field_inclusion(changeset, field, opts) do
    with {:ok, values} <- get_option(opts, :in) do
      message = extract_message(opts, :in) || "is invalid"
      validate_inclusion(changeset, field, values, message: message)
    else
      _ -> changeset
    end
  end

  defp validate_field_exclusion(changeset, field, opts) do
    with {:ok, values} <- get_option(opts, :not_in) do
      message = extract_message(opts, :not_in) || "is reserved"
      validate_exclusion(changeset, field, values, message: message)
    else
      _ -> changeset
    end
  end

  # Helper to get option value
  defp get_option(opts, key) do
    case opts[key] do
      nil -> :error
      value -> {:ok, value}
    end
  end

  # Extract message from options
  defp extract_message(opts, key) do
    case opts[key] do
      {_, [message: msg]} -> msg
      _ -> Messages.get_from_opts(opts, key)
    end
  end
end
