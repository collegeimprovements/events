defmodule OmSchema.CustomValidators do
  @moduledoc """
  Composable custom validators for OmSchema fields.

  Allows defining and applying custom validation functions to changesets
  in a declarative way using the `:validators` field option.

  ## Usage

  Add custom validators to a field using the `:validators` option:

      field :credit_card, :string, validators: [
        {MyApp.Validators, :validate_luhn},
        &validate_card_format/2
      ]

      field :html_content, :string, validators: [
        {OmSchema.CustomValidators, :validate_no_html}
      ]

  ## Validator Formats

  Validators can be specified in several formats:

  ### Module/Function/Args Tuple

      {MyModule, :function_name, [extra_arg]}
      # Called as: MyModule.function_name(changeset, field, extra_arg)

  ### Module/Function Tuple

      {MyModule, :function_name}
      # Called as: MyModule.function_name(changeset, field)

  ### Anonymous Function (Arity 1)

      &validate_something/1
      # Called as: validate_something(changeset)
      # Note: field is not passed, function should know which field to validate

  ### Anonymous Function (Arity 2)

      &validate_something/2
      # Called as: validate_something(changeset, field)

  ## Writing Custom Validators

  Custom validators should follow this pattern:

      def my_validator(changeset, field, opts \\\\ []) do
        value = Ecto.Changeset.get_change(changeset, field)

        if value && !valid?(value, opts) do
          Ecto.Changeset.add_error(changeset, field, "is invalid")
        else
          changeset
        end
      end

  ## Built-in Validators

  This module provides several built-in validators:

    * `validate_luhn/2` - Luhn algorithm validation (credit cards)
    * `validate_no_html/2` - Rejects HTML content
    * `validate_no_profanity/3` - Checks against profanity word list
    * `validate_json/2` - Validates JSON string format
    * `validate_base64/2` - Validates base64 encoding
    * `validate_alphanumeric/2` - Only letters and numbers
    * `validate_printable/2` - Only printable characters

  """

  import Ecto.Changeset

  @doc """
  Applies a list of validators to a changeset for a specific field.

  ## Examples

      changeset
      |> CustomValidators.apply_validators(:credit_card, [
        {MyApp.Validators, :validate_luhn}
      ])

  """
  @spec apply_validators(Ecto.Changeset.t(), atom(), list()) :: Ecto.Changeset.t()
  def apply_validators(changeset, field, validators) when is_list(validators) do
    Enum.reduce(validators, changeset, fn validator, acc ->
      apply_validator(acc, field, validator)
    end)
  end

  @doc """
  Applies a single validator to a changeset.

  Supports multiple validator formats:
    * `{Module, :function, args}` - MFA with extra args
    * `{Module, :function}` - MFA without extra args
    * Anonymous function with arity 1 or 2

  """
  @spec apply_validator(Ecto.Changeset.t(), atom(), tuple() | function()) :: Ecto.Changeset.t()
  def apply_validator(changeset, field, {module, function, args})
      when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, [changeset, field | args])
  end

  def apply_validator(changeset, field, {module, function})
      when is_atom(module) and is_atom(function) do
    apply(module, function, [changeset, field])
  end

  def apply_validator(changeset, _field, fun) when is_function(fun, 1) do
    fun.(changeset)
  end

  def apply_validator(changeset, field, fun) when is_function(fun, 2) do
    fun.(changeset, field)
  end

  # ============================================
  # Built-in Validators
  # ============================================

  @doc """
  Validates a value using the Luhn algorithm (used for credit card numbers).

  ## Examples

      field :card_number, :string, validators: [
        {OmSchema.CustomValidators, :validate_luhn}
      ]

  """
  @spec validate_luhn(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_luhn(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn _, value ->
      if luhn_valid?(value) do
        []
      else
        message = Keyword.get(opts, :message, "is not a valid number")
        [{field, message}]
      end
    end)
  end

  @doc """
  Validates that a string does not contain HTML tags.

  Useful for preventing XSS attacks in user input.

  ## Options

    * `:message` - Custom error message (default: "must not contain HTML")

  ## Examples

      field :bio, :string, validators: [
        {OmSchema.CustomValidators, :validate_no_html}
      ]

  """
  @spec validate_no_html(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_no_html(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn _, value ->
      if contains_html?(value) do
        message = Keyword.get(opts, :message, "must not contain HTML")
        [{field, message}]
      else
        []
      end
    end)
  end

  @doc """
  Validates that a string does not contain words from a prohibited list.

  ## Options

    * `:words` - List of prohibited words (required)
    * `:message` - Custom error message (default: "contains prohibited content")

  ## Examples

      field :comment, :string, validators: [
        {OmSchema.CustomValidators, :validate_no_profanity, [[words: ["spam", "bad"]]]}
      ]

  """
  @spec validate_no_profanity(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_no_profanity(changeset, field, opts \\ []) do
    words = Keyword.get(opts, :words, [])

    validate_change(changeset, field, fn _, value ->
      downcased = String.downcase(value)

      if Enum.any?(words, &String.contains?(downcased, String.downcase(&1))) do
        message = Keyword.get(opts, :message, "contains prohibited content")
        [{field, message}]
      else
        []
      end
    end)
  end

  @doc """
  Validates that a string is valid JSON.

  **Note:** Requires the `Jason` library. If Jason is not available,
  use a JSON decoder that is available in your project.

  ## Options

    * `:message` - Custom error message (default: "is not valid JSON")
    * `:decoder` - Custom JSON decoder module (default: Jason)

  ## Examples

      field :config, :string, validators: [
        {OmSchema.CustomValidators, :validate_json}
      ]

      # With custom decoder
      field :config, :string, validators: [
        {OmSchema.CustomValidators, :validate_json, [[decoder: Poison]]}
      ]

  """
  @spec validate_json(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_json(changeset, field, opts \\ []) do
    decoder = Keyword.get(opts, :decoder, Jason)

    unless Code.ensure_loaded?(decoder) do
      raise ArgumentError, """
      JSON decoder #{inspect(decoder)} is not available.
      Add :jason to your dependencies or specify a custom decoder:

          {OmSchema.CustomValidators, :validate_json, [[decoder: YourDecoder]]}
      """
    end

    validate_change(changeset, field, fn _, value ->
      case decoder.decode(value) do
        {:ok, _} ->
          []

        {:error, _} ->
          message = Keyword.get(opts, :message, "is not valid JSON")
          [{field, message}]
      end
    end)
  end

  @doc """
  Validates that a string is valid base64 encoding.

  ## Options

    * `:message` - Custom error message (default: "is not valid base64")

  ## Examples

      field :encoded_data, :string, validators: [
        {OmSchema.CustomValidators, :validate_base64}
      ]

  """
  @spec validate_base64(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_base64(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn _, value ->
      case Base.decode64(value) do
        {:ok, _} ->
          []

        :error ->
          message = Keyword.get(opts, :message, "is not valid base64")
          [{field, message}]
      end
    end)
  end

  @doc """
  Validates that a string contains only alphanumeric characters.

  ## Options

    * `:message` - Custom error message (default: "must contain only letters and numbers")

  ## Examples

      field :code, :string, validators: [
        {OmSchema.CustomValidators, :validate_alphanumeric}
      ]

  """
  @spec validate_alphanumeric(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_alphanumeric(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn _, value ->
      if String.match?(value, ~r/^[a-zA-Z0-9]*$/) do
        []
      else
        message = Keyword.get(opts, :message, "must contain only letters and numbers")
        [{field, message}]
      end
    end)
  end

  @doc """
  Validates that a string contains only printable ASCII characters.

  ## Options

    * `:message` - Custom error message (default: "must contain only printable characters")

  ## Examples

      field :display_name, :string, validators: [
        {OmSchema.CustomValidators, :validate_printable}
      ]

  """
  @spec validate_printable(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_printable(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn _, value ->
      if String.printable?(value) do
        []
      else
        message = Keyword.get(opts, :message, "must contain only printable characters")
        [{field, message}]
      end
    end)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp luhn_valid?(value) when is_binary(value) do
    # Remove spaces and dashes
    digits =
      value
      |> String.replace(~r/[\s\-]/, "")
      |> String.graphemes()
      |> Enum.reverse()

    # Validate all characters are digits
    if Enum.all?(digits, &String.match?(&1, ~r/^\d$/)) do
      sum =
        digits
        |> Enum.with_index()
        |> Enum.reduce(0, fn {digit, index}, acc ->
          n = String.to_integer(digit)

          if rem(index, 2) == 1 do
            doubled = n * 2
            acc + if(doubled > 9, do: doubled - 9, else: doubled)
          else
            acc + n
          end
        end)

      rem(sum, 10) == 0
    else
      false
    end
  end

  defp luhn_valid?(_), do: false

  defp contains_html?(value) when is_binary(value) do
    # Check for HTML tags
    String.match?(value, ~r/<[^>]+>/)
  end

  defp contains_html?(_), do: false
end
