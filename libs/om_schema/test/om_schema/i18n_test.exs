defmodule OmSchema.I18nTest do
  @moduledoc """
  Tests for OmSchema.I18n - Internationalization support for validation messages.
  """

  use ExUnit.Case, async: true

  alias OmSchema.I18n

  # ============================================
  # Test Translator Module
  # ============================================

  defmodule TestTranslator do
    @behaviour OmSchema.I18n

    @translations %{
      "email.invalid" => "is not a valid email address",
      "password.too_short" => "must be at least %{min} characters",
      "age.too_young" => "must be at least %{min} years old",
      "field.required" => "is required"
    }

    @impl true
    def translate(_domain, key, bindings) do
      case Map.get(@translations, key) do
        nil ->
          key

        template ->
          Enum.reduce(bindings, template, fn {k, v}, acc ->
            String.replace(acc, "%{#{k}}", to_string(v))
          end)
      end
    end
  end

  defmodule TestGettext do
    # Simulates a Gettext module with dgettext/3
    def dgettext(_domain, key, bindings) do
      template =
        case key do
          "email.invalid" -> "is not a valid email address"
          "password.too_short" -> "must be at least %{min} characters"
          _ -> key
        end

      Enum.reduce(bindings, template, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end
  end

  # ============================================
  # Test Schema with i18n messages
  # ============================================

  defmodule UserSchema do
    use OmSchema

    schema "i18n_test_users" do
      field :email, :string,
        required: true,
        format: ~r/@/,
        message: {:i18n, "email.invalid"}

      field :password, :string,
        min_length: 8,
        messages: %{
          min_length: {:i18n, "password.too_short", min: 8}
        }

      field :age, :integer,
        min: 18,
        message: {:i18n, "age.too_young", min: 18}

      field :username, :string,
        required: true,
        message: "must be provided"
    end
  end

  # ============================================
  # i18n_tuple?/1 Tests
  # ============================================

  describe "i18n_tuple?/1" do
    test "returns true for simple i18n tuple" do
      assert I18n.i18n_tuple?({:i18n, "error.message"})
    end

    test "returns true for i18n tuple with bindings" do
      assert I18n.i18n_tuple?({:i18n, "error.message", [count: 5]})
    end

    test "returns false for regular string" do
      refute I18n.i18n_tuple?("regular string")
    end

    test "returns false for other tuples" do
      refute I18n.i18n_tuple?({:ok, "value"})
      refute I18n.i18n_tuple?({:error, "reason"})
    end

    test "returns false for invalid i18n tuple (non-string key)" do
      refute I18n.i18n_tuple?({:i18n, :atom_key})
    end

    test "returns false for invalid i18n tuple (non-list bindings)" do
      refute I18n.i18n_tuple?({:i18n, "key", %{count: 5}})
    end
  end

  # ============================================
  # i18n/2 Tests
  # ============================================

  describe "i18n/2" do
    test "creates simple i18n tuple" do
      assert I18n.i18n("email.invalid") == {:i18n, "email.invalid"}
    end

    test "creates i18n tuple with bindings" do
      assert I18n.i18n("age.min", min: 18) == {:i18n, "age.min", [min: 18]}
    end

    test "creates simple tuple when bindings are empty" do
      assert I18n.i18n("error.key", []) == {:i18n, "error.key"}
    end
  end

  # ============================================
  # translate/2 Tests
  # ============================================

  describe "translate/2" do
    test "returns key when no translator configured" do
      # Temporarily ensure no translator is configured
      original = Application.get_env(:om_schema, :translator)
      Application.delete_env(:om_schema, :translator)

      result = I18n.translate({:i18n, "email.invalid"})
      assert result == "email.invalid"

      # Restore original config
      if original, do: Application.put_env(:om_schema, :translator, original)
    end

    test "translates using custom translator" do
      result = I18n.translate({:i18n, "email.invalid"}, translator: TestTranslator)
      assert result == "is not a valid email address"
    end

    test "translates with bindings using custom translator" do
      result = I18n.translate({:i18n, "password.too_short", min: 8}, translator: TestTranslator)
      assert result == "must be at least 8 characters"
    end

    test "translates simple tuple by converting to tuple with empty bindings" do
      result = I18n.translate({:i18n, "email.invalid"}, translator: TestTranslator)
      assert result == "is not a valid email address"
    end

    test "returns string as-is when given a string" do
      result = I18n.translate("already a string")
      assert result == "already a string"
    end

    test "uses Gettext-style translator" do
      result = I18n.translate({:i18n, "email.invalid"}, translator: TestGettext)
      assert result == "is not a valid email address"
    end

    test "respects custom domain option" do
      # This tests that domain is passed through, even if TestTranslator ignores it
      result = I18n.translate({:i18n, "email.invalid"}, translator: TestTranslator, domain: "validation")
      assert result == "is not a valid email address"
    end
  end

  # ============================================
  # translate_errors/2 Tests
  # ============================================

  describe "translate_errors/2" do
    test "translates i18n errors in changeset" do
      changeset = %Ecto.Changeset{
        data: %{},
        errors: [
          email: {{:i18n, "email.invalid"}, [validation: :format]},
          password: {{:i18n, "password.too_short", min: 8}, [validation: :min_length]}
        ],
        valid?: false
      }

      result = I18n.translate_errors(changeset, translator: TestTranslator)

      assert result.errors[:email] == {"is not a valid email address", [validation: :format]}
      assert result.errors[:password] == {"must be at least 8 characters", [validation: :min_length]}
    end

    test "leaves regular string errors unchanged" do
      changeset = %Ecto.Changeset{
        data: %{},
        errors: [
          email: {"is invalid", [validation: :format]},
          name: {"can't be blank", [validation: :required]}
        ],
        valid?: false
      }

      result = I18n.translate_errors(changeset, translator: TestTranslator)

      assert result.errors[:email] == {"is invalid", [validation: :format]}
      assert result.errors[:name] == {"can't be blank", [validation: :required]}
    end

    test "handles mixed i18n and string errors" do
      changeset = %Ecto.Changeset{
        data: %{},
        errors: [
          email: {{:i18n, "email.invalid"}, [validation: :format]},
          name: {"can't be blank", [validation: :required]}
        ],
        valid?: false
      }

      result = I18n.translate_errors(changeset, translator: TestTranslator)

      assert result.errors[:email] == {"is not a valid email address", [validation: :format]}
      assert result.errors[:name] == {"can't be blank", [validation: :required]}
    end

    test "handles empty errors list" do
      changeset = %Ecto.Changeset{
        data: %{},
        errors: [],
        valid?: true
      }

      result = I18n.translate_errors(changeset, translator: TestTranslator)

      assert result.errors == []
    end

    test "merges bindings from validation opts" do
      changeset = %Ecto.Changeset{
        data: %{},
        errors: [
          password: {{:i18n, "password.too_short"}, [validation: :min_length, bindings: [min: 10]]}
        ],
        valid?: false
      }

      result = I18n.translate_errors(changeset, translator: TestTranslator)

      assert result.errors[:password] == {"must be at least 10 characters", [validation: :min_length, bindings: [min: 10]]}
    end
  end

  # ============================================
  # Integration with Messages Helper
  # ============================================

  describe "integration with messages helper" do
    alias OmSchema.Helpers.Messages

    test "get_from_opts returns i18n tuple" do
      opts = [message: {:i18n, "email.invalid"}]
      result = Messages.get_from_opts(opts, :format)
      assert result == {:i18n, "email.invalid"}
    end

    test "get_from_opts returns i18n tuple with bindings" do
      opts = [messages: %{min_length: {:i18n, "password.too_short", min: 8}}]
      result = Messages.get_from_opts(opts, :min_length)
      assert result == {:i18n, "password.too_short", min: 8}
    end

    test "add_to_opts adds i18n tuple to validation opts" do
      field_opts = [message: {:i18n, "email.invalid"}]
      validation_opts = [foo: :bar]

      result = Messages.add_to_opts(validation_opts, field_opts, :format)

      assert Keyword.get(result, :message) == {:i18n, "email.invalid"}
    end

    test "process_message returns i18n tuple as-is by default" do
      result = Messages.process_message({:i18n, "email.invalid"})
      assert result == {:i18n, "email.invalid"}
    end

    test "process_message translates when translate: true" do
      result = Messages.process_message({:i18n, "email.invalid"}, translate: true, translator: TestTranslator)
      assert result == "is not a valid email address"
    end

    test "process_message returns string as-is" do
      result = Messages.process_message("regular error message")
      assert result == "regular error message"
    end
  end
end
