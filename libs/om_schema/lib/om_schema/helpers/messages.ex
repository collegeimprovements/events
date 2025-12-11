defmodule OmSchema.Helpers.Messages do
  @moduledoc """
  Helper functions for managing validation error messages.

  Provides utilities for extracting and adding custom error messages from field options.
  """

  @doc """
  Get message from field options, checking both :message and :messages map.
  """
  def get_from_opts(field_opts, validation_type) do
    cond do
      # Check messages map first (more specific)
      messages = field_opts[:messages] ->
        messages[validation_type]

      # Fall back to general message
      message = field_opts[:message] ->
        message

      true ->
        nil
    end
  end

  @doc """
  Add message to validation options if present in field options.
  """
  def add_to_opts(validation_opts, field_opts, validation_type) do
    if msg = get_from_opts(field_opts, validation_type) do
      Keyword.put(validation_opts, :message, msg)
    else
      validation_opts
    end
  end
end
