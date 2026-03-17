defmodule OmSchema.CustomValidatorsTest do
  @moduledoc """
  Tests for OmSchema.CustomValidators - Composable custom validation functions.

  Validates that custom validators can be defined and applied in various formats:
  - Module/Function/Args tuples
  - Module/Function tuples
  - Anonymous functions (arity 1 and 2)
  """

  use ExUnit.Case, async: true

  alias OmSchema.CustomValidators

  # Test schema using embedded_schema to avoid database
  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :credit_card, :string
      field :bio, :string
      field :comment, :string
      field :config, :string
      field :encoded_data, :string
      field :code, :string
      field :display_name, :string
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [
        :credit_card,
        :bio,
        :comment,
        :config,
        :encoded_data,
        :code,
        :display_name
      ])
    end
  end

  defp changeset(attrs) do
    TestSchema.changeset(%TestSchema{}, attrs)
  end

  # ============================================
  # apply_validators/3
  # ============================================

  describe "apply_validators/3" do
    test "applies multiple validators in sequence" do
      validators = [
        {CustomValidators, :validate_alphanumeric},
        {CustomValidators, :validate_printable}
      ]

      cs = changeset(%{code: "abc123"})
      result = CustomValidators.apply_validators(cs, :code, validators)

      assert result.valid?
    end

    test "stops on first error (short-circuits)" do
      validators = [
        {CustomValidators, :validate_alphanumeric},
        {CustomValidators, :validate_printable}
      ]

      cs = changeset(%{code: "abc-123!"})
      result = CustomValidators.apply_validators(cs, :code, validators)

      refute result.valid?
      assert result.errors[:code] != nil
    end

    test "handles empty validator list" do
      cs = changeset(%{code: "abc123"})
      result = CustomValidators.apply_validators(cs, :code, [])

      assert result.valid?
    end
  end

  # ============================================
  # apply_validator/3 - Different Formats
  # ============================================

  describe "apply_validator/3 with {Module, :function, args}" do
    test "calls function with changeset, field, and extra args" do
      opts = [words: ["spam"]]
      cs = changeset(%{comment: "This is spam content"})

      result = CustomValidators.apply_validator(
        cs,
        :comment,
        {CustomValidators, :validate_no_profanity, [opts]}
      )

      refute result.valid?
    end
  end

  describe "apply_validator/3 with {Module, :function}" do
    test "calls function with changeset and field" do
      cs = changeset(%{bio: "<script>alert('xss')</script>"})

      result = CustomValidators.apply_validator(
        cs,
        :bio,
        {CustomValidators, :validate_no_html}
      )

      refute result.valid?
      assert result.errors[:bio] != nil
    end
  end

  describe "apply_validator/3 with arity-1 function" do
    test "calls function with changeset only" do
      validator = fn changeset ->
        if Ecto.Changeset.get_change(changeset, :code) == "forbidden" do
          Ecto.Changeset.add_error(changeset, :code, "is forbidden")
        else
          changeset
        end
      end

      cs = changeset(%{code: "forbidden"})
      result = CustomValidators.apply_validator(cs, :code, validator)

      refute result.valid?
    end
  end

  describe "apply_validator/3 with arity-2 function" do
    test "calls function with changeset and field" do
      validator = fn changeset, field ->
        value = Ecto.Changeset.get_change(changeset, field)

        if value && String.length(value) > 5 do
          changeset
        else
          Ecto.Changeset.add_error(changeset, field, "is too short")
        end
      end

      cs = changeset(%{code: "abc"})
      result = CustomValidators.apply_validator(cs, :code, validator)

      refute result.valid?
      assert result.errors[:code] != nil
    end
  end

  # ============================================
  # Built-in Validators
  # ============================================

  describe "validate_luhn/2" do
    test "validates valid credit card numbers" do
      # Test Visa number (passes Luhn)
      cs = changeset(%{credit_card: "4111111111111111"})
      result = CustomValidators.validate_luhn(cs, :credit_card)

      assert result.valid?
    end

    test "validates card number with spaces" do
      cs = changeset(%{credit_card: "4111 1111 1111 1111"})
      result = CustomValidators.validate_luhn(cs, :credit_card)

      assert result.valid?
    end

    test "validates card number with dashes" do
      cs = changeset(%{credit_card: "4111-1111-1111-1111"})
      result = CustomValidators.validate_luhn(cs, :credit_card)

      assert result.valid?
    end

    test "fails for invalid numbers" do
      cs = changeset(%{credit_card: "1234567890123456"})
      result = CustomValidators.validate_luhn(cs, :credit_card)

      refute result.valid?
    end

    test "fails for non-numeric input" do
      cs = changeset(%{credit_card: "abcd1234"})
      result = CustomValidators.validate_luhn(cs, :credit_card)

      refute result.valid?
    end

    test "uses custom message" do
      cs = changeset(%{credit_card: "invalid"})
      result = CustomValidators.validate_luhn(cs, :credit_card, message: "invalid card")

      {message, _} = result.errors[:credit_card]
      assert message == "invalid card"
    end
  end

  describe "validate_no_html/2" do
    test "passes for plain text" do
      cs = changeset(%{bio: "Hello, I am a developer."})
      result = CustomValidators.validate_no_html(cs, :bio)

      assert result.valid?
    end

    test "fails for HTML tags" do
      cs = changeset(%{bio: "Hello <b>world</b>"})
      result = CustomValidators.validate_no_html(cs, :bio)

      refute result.valid?
    end

    test "fails for script tags" do
      cs = changeset(%{bio: "<script>alert('xss')</script>"})
      result = CustomValidators.validate_no_html(cs, :bio)

      refute result.valid?
    end

    test "uses custom message" do
      cs = changeset(%{bio: "<div>test</div>"})
      result = CustomValidators.validate_no_html(cs, :bio, message: "no HTML allowed")

      {message, _} = result.errors[:bio]
      assert message == "no HTML allowed"
    end
  end

  describe "validate_no_profanity/3" do
    test "passes for clean content" do
      cs = changeset(%{comment: "This is a nice comment"})
      result = CustomValidators.validate_no_profanity(cs, :comment, words: ["bad", "spam"])

      assert result.valid?
    end

    test "fails when containing prohibited words" do
      cs = changeset(%{comment: "This is a spam message"})
      result = CustomValidators.validate_no_profanity(cs, :comment, words: ["spam"])

      refute result.valid?
    end

    test "is case-insensitive" do
      cs = changeset(%{comment: "This is SPAM"})
      result = CustomValidators.validate_no_profanity(cs, :comment, words: ["spam"])

      refute result.valid?
    end
  end

  describe "validate_json/2" do
    @tag :skip_without_jason
    test "passes for valid JSON" do
      if Code.ensure_loaded?(Jason) do
        cs = changeset(%{config: ~s({"key": "value"})})
        result = CustomValidators.validate_json(cs, :config)

        assert result.valid?
      end
    end

    @tag :skip_without_jason
    test "passes for JSON array" do
      if Code.ensure_loaded?(Jason) do
        cs = changeset(%{config: ~s([1, 2, 3])})
        result = CustomValidators.validate_json(cs, :config)

        assert result.valid?
      end
    end

    @tag :skip_without_jason
    test "fails for invalid JSON" do
      if Code.ensure_loaded?(Jason) do
        cs = changeset(%{config: "not json"})
        result = CustomValidators.validate_json(cs, :config)

        refute result.valid?
      end
    end

    @tag :skip_without_jason
    test "fails for malformed JSON" do
      if Code.ensure_loaded?(Jason) do
        cs = changeset(%{config: ~s({"key": })})
        result = CustomValidators.validate_json(cs, :config)

        refute result.valid?
      end
    end

    test "raises when decoder not available" do
      cs = changeset(%{config: ~s({"key": "value"})})

      assert_raise ArgumentError, ~r/JSON decoder.*is not available/, fn ->
        CustomValidators.validate_json(cs, :config, decoder: NonExistentModule)
      end
    end
  end

  describe "validate_base64/2" do
    test "passes for valid base64" do
      cs = changeset(%{encoded_data: Base.encode64("hello")})
      result = CustomValidators.validate_base64(cs, :encoded_data)

      assert result.valid?
    end

    test "fails for invalid base64" do
      cs = changeset(%{encoded_data: "not!valid@base64"})
      result = CustomValidators.validate_base64(cs, :encoded_data)

      refute result.valid?
    end
  end

  describe "validate_alphanumeric/2" do
    test "passes for alphanumeric string" do
      cs = changeset(%{code: "abc123XYZ"})
      result = CustomValidators.validate_alphanumeric(cs, :code)

      assert result.valid?
    end

    test "fails for string with special characters" do
      cs = changeset(%{code: "abc-123"})
      result = CustomValidators.validate_alphanumeric(cs, :code)

      refute result.valid?
    end

    test "fails for string with spaces" do
      cs = changeset(%{code: "abc 123"})
      result = CustomValidators.validate_alphanumeric(cs, :code)

      refute result.valid?
    end
  end

  describe "validate_printable/2" do
    test "passes for printable string" do
      cs = changeset(%{display_name: "John Doe - Developer"})
      result = CustomValidators.validate_printable(cs, :display_name)

      assert result.valid?
    end

    test "fails for string with control characters" do
      cs = changeset(%{display_name: "Hello\x00World"})
      result = CustomValidators.validate_printable(cs, :display_name)

      refute result.valid?
    end
  end

  # ============================================
  # Integration with OmSchema
  # ============================================

  describe "integration with OmSchema :validators option" do
    defmodule IntegrationSchema do
      use OmSchema

      schema "integration_test" do
        field :card_number, :string, validators: [
          {OmSchema.CustomValidators, :validate_luhn}
        ]

        field :safe_content, :string, validators: [
          {OmSchema.CustomValidators, :validate_no_html},
          {OmSchema.CustomValidators, :validate_printable}
        ]
      end
    end

    test "validates field using declared validators" do
      cs = IntegrationSchema.base_changeset(%IntegrationSchema{}, %{
        card_number: "4111111111111111",
        safe_content: "Hello world"
      })

      assert cs.valid?
    end

    test "fails when validator fails" do
      cs = IntegrationSchema.base_changeset(%IntegrationSchema{}, %{
        card_number: "invalid-card",
        safe_content: "Hello world"
      })

      refute cs.valid?
      assert cs.errors[:card_number] != nil
    end

    test "runs multiple validators on same field" do
      cs = IntegrationSchema.base_changeset(%IntegrationSchema{}, %{
        card_number: "4111111111111111",
        safe_content: "<script>bad</script>"
      })

      refute cs.valid?
      assert cs.errors[:safe_content] != nil
    end
  end
end
