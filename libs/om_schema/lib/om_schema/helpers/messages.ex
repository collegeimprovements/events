defmodule OmSchema.Helpers.Messages do
  @moduledoc """
  Helper functions for managing validation error messages.

  Provides utilities for extracting and adding custom error messages from field options.

  ## I18n Support

  Messages can be specified as i18n tuples for translation:

      field :email, :string, message: {:i18n, "email.invalid"}
      field :age, :integer, message: {:i18n, "age.too_young", min: 18}

  See `OmSchema.I18n` for configuration and usage details.
  """

  alias OmSchema.I18n

  @doc """
  Get message from field options, checking both :message and :messages map.

  Returns the message as-is (may be a string or i18n tuple).
  """
  @spec get_from_opts(keyword(), atom()) :: String.t() | I18n.i18n_tuple() | nil
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

  If the message is an i18n tuple, it's preserved as-is for lazy translation.
  """
  @spec add_to_opts(keyword(), keyword(), atom()) :: keyword()
  def add_to_opts(validation_opts, field_opts, validation_type) do
    case get_from_opts(field_opts, validation_type) do
      nil ->
        validation_opts

      msg ->
        Keyword.put(validation_opts, :message, process_message(msg))
    end
  end

  @doc """
  Processes a message, translating i18n tuples if a translator is configured.

  For immediate translation (not recommended, prefer lazy translation):

      process_message({:i18n, "error.key"}, translate: true)

  """
  @spec process_message(String.t() | I18n.i18n_tuple(), keyword()) :: String.t() | I18n.i18n_tuple()
  def process_message(message, opts \\ [])

  def process_message(message, _opts) when is_binary(message) do
    message
  end

  def process_message({:i18n, _key} = tuple, opts) do
    if Keyword.get(opts, :translate, false) do
      I18n.translate(tuple, opts)
    else
      # Return as-is for lazy translation
      tuple
    end
  end

  def process_message({:i18n, _key, _bindings} = tuple, opts) do
    if Keyword.get(opts, :translate, false) do
      I18n.translate(tuple, opts)
    else
      # Return as-is for lazy translation
      tuple
    end
  end

  def process_message(other, _opts) do
    # Unknown message format, return as-is
    other
  end
end
