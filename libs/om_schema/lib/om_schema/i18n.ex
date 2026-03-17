defmodule OmSchema.I18n do
  @moduledoc """
  Internationalization (i18n) support for OmSchema validation messages.

  Enables validation error messages to be translated using Gettext or any
  compatible translation backend.

  ## Configuration

  Configure the translator module in your application config:

      config :om_schema, translator: MyApp.Gettext

  Or specify a custom translator module that implements `translate/3`:

      config :om_schema, translator: MyApp.CustomTranslator

  ## Usage

  Use the `{:i18n, key}` or `{:i18n, key, bindings}` tuple format for messages:

      # Simple key
      field :email, :string, message: {:i18n, "email.invalid"}

      # With bindings
      field :age, :integer, message: {:i18n, "age.too_young", min: 18}

      # Per-validation messages
      field :password, :string,
        messages: %{
          min_length: {:i18n, "password.too_short", min: 8},
          format: {:i18n, "password.format_invalid"}
        }

  ## Translation Function

  When translation is needed, the configured translator is called:

      # For Gettext
      MyApp.Gettext.dgettext("errors", key, bindings)

      # For custom translator
      MyApp.CustomTranslator.translate("errors", key, bindings)

  ## Custom Translator Module

  To implement a custom translator:

      defmodule MyApp.CustomTranslator do
        @behaviour OmSchema.I18n.Translator

        def translate(domain, key, bindings) do
          # Your translation logic here
        end
      end

  ## Lazy Translation

  Messages are not translated until the changeset errors are retrieved.
  This ensures proper locale context at the time of rendering.

  To translate errors in a changeset:

      OmSchema.I18n.translate_errors(changeset)

  """

  @doc """
  Behaviour for custom translator modules.
  """
  @callback translate(domain :: String.t(), key :: String.t(), bindings :: keyword()) ::
              String.t()

  @type i18n_tuple :: {:i18n, String.t()} | {:i18n, String.t(), keyword()}

  @doc """
  Checks if a value is an i18n tuple.

  ## Examples

      iex> OmSchema.I18n.i18n_tuple?({:i18n, "error.message"})
      true

      iex> OmSchema.I18n.i18n_tuple?({:i18n, "error.message", [count: 5]})
      true

      iex> OmSchema.I18n.i18n_tuple?("regular string")
      false

  """
  @spec i18n_tuple?(term()) :: boolean()
  def i18n_tuple?({:i18n, key}) when is_binary(key), do: true
  def i18n_tuple?({:i18n, key, bindings}) when is_binary(key) and is_list(bindings), do: true
  def i18n_tuple?(_), do: false

  @doc """
  Translates an i18n tuple using the configured translator.

  Returns the translated string, or the key itself if no translator is configured.

  ## Options

    * `:domain` - Translation domain (default: "errors")
    * `:translator` - Override the configured translator module

  ## Examples

      iex> OmSchema.I18n.translate({:i18n, "email.invalid"})
      "is invalid"  # or translated version

      iex> OmSchema.I18n.translate({:i18n, "age.min", min: 18})
      "must be at least 18"

  """
  @spec translate(i18n_tuple(), keyword()) :: String.t()
  def translate(tuple, opts \\ [])

  def translate({:i18n, key}, opts) do
    translate({:i18n, key, []}, opts)
  end

  def translate({:i18n, key, bindings}, opts) do
    domain = Keyword.get(opts, :domain, "errors")
    translator = Keyword.get(opts, :translator) || get_translator()

    case translator do
      nil ->
        # No translator configured, return the key
        key

      module when is_atom(module) ->
        do_translate(module, domain, key, bindings)
    end
  end

  def translate(message, _opts) when is_binary(message) do
    # Already a string, return as-is
    message
  end

  @doc """
  Translates all i18n error messages in a changeset.

  ## Options

    * `:domain` - Translation domain (default: "errors")
    * `:translator` - Override the configured translator module

  ## Examples

      changeset
      |> MySchema.changeset(attrs)
      |> OmSchema.I18n.translate_errors()

  """
  @spec translate_errors(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()
  def translate_errors(%Ecto.Changeset{} = changeset, opts \\ []) do
    translated_errors =
      Enum.map(changeset.errors, fn {field, {message, validation_opts}} ->
        translated_message =
          if i18n_tuple?(message) do
            # Merge validation opts as bindings
            bindings = Keyword.get(validation_opts, :bindings, [])

            case message do
              {:i18n, key} -> translate({:i18n, key, bindings}, opts)
              {:i18n, key, extra} -> translate({:i18n, key, Keyword.merge(extra, bindings)}, opts)
            end
          else
            message
          end

        {field, {translated_message, validation_opts}}
      end)

    %{changeset | errors: translated_errors}
  end

  @doc """
  Wraps a message string in an i18n tuple.

  Convenience function for creating i18n tuples programmatically.

  ## Examples

      iex> OmSchema.I18n.i18n("email.invalid")
      {:i18n, "email.invalid"}

      iex> OmSchema.I18n.i18n("age.min", min: 18)
      {:i18n, "age.min", [min: 18]}

  """
  @spec i18n(String.t(), keyword()) :: i18n_tuple()
  def i18n(key, bindings \\ [])
  def i18n(key, []), do: {:i18n, key}
  def i18n(key, bindings), do: {:i18n, key, bindings}

  # Private helpers

  defp get_translator do
    Application.get_env(:om_schema, :translator)
  end

  defp do_translate(module, domain, key, bindings) do
    cond do
      # Check for Gettext module (has dgettext/3)
      function_exported?(module, :dgettext, 3) ->
        apply(module, :dgettext, [domain, key, bindings])

      # Check for custom translator (has translate/3)
      function_exported?(module, :translate, 3) ->
        apply(module, :translate, [domain, key, bindings])

      # Fallback: just return the key
      true ->
        key
    end
  end
end
