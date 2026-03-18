defmodule OmSchema.ErrorsTest do
  @moduledoc """
  Tests for OmSchema.Errors - Error handling and prioritization.

  Validates error sorting by priority, grouping, formatting, counting,
  merging, clearing, and context decoration on Ecto changesets.

  ## Priority Order

  1. required/cast (highest)
  2. type
  3. format/acceptance/confirmation
  4. length
  5. unique/foreign_key/check
  6. custom (lowest)
  """

  use ExUnit.Case, async: true

  alias OmSchema.Errors

  # ============================================
  # Test Schema
  # ============================================

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :name, :string
      field :email, :string
      field :age, :integer
      field :status, :string
      field :code, :string
    end

    def changeset(struct \\ %__MODULE__{}, attrs) do
      struct
      |> cast(attrs, [:name, :email, :age, :status, :code])
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp changeset(attrs) do
    TestSchema.changeset(%TestSchema{}, attrs)
  end

  defp changeset_with_required_error do
    changeset(%{})
    |> Ecto.Changeset.validate_required([:name])
  end

  defp changeset_with_format_error do
    changeset(%{email: "invalid"})
    |> Ecto.Changeset.validate_format(:email, ~r/@/, message: "must contain @")
  end

  defp changeset_with_length_error do
    changeset(%{name: "ab"})
    |> Ecto.Changeset.validate_length(:name, min: 3)
  end

  defp changeset_with_multiple_errors do
    changeset(%{name: "ab", email: "invalid"})
    |> Ecto.Changeset.validate_required([:status])
    |> Ecto.Changeset.validate_length(:name, min: 3)
    |> Ecto.Changeset.validate_format(:email, ~r/@/)
  end

  defp changeset_with_custom_error do
    changeset(%{name: "test"})
    |> Ecto.Changeset.add_error(:name, "custom validation failed", validation: :custom)
  end

  defp changeset_with_unique_error do
    changeset(%{email: "test@example.com"})
    |> Ecto.Changeset.add_error(:email, "has already been taken", validation: :unique)
  end

  defp changeset_with_acceptance_error do
    changeset(%{})
    |> Ecto.Changeset.add_error(:status, "must be accepted", validation: :acceptance)
  end

  # ============================================
  # prioritize/1
  # ============================================

  describe "prioritize/1" do
    test "returns empty list for changeset with no errors" do
      assert Errors.prioritize(changeset(%{name: "test"})) == []
    end

    test "returns errors sorted by priority" do
      cs =
        changeset(%{name: "ab", email: "bad"})
        |> Ecto.Changeset.validate_required([:status])
        |> Ecto.Changeset.validate_length(:name, min: 5)
        |> Ecto.Changeset.add_error(:email, "has already been taken", validation: :unique)

      prioritized = Errors.prioritize(cs)

      # required (priority 1) should come before length (priority 4)
      # which should come before unique (priority 5)
      fields_in_order = Enum.map(prioritized, fn {field, _} -> field end)
      status_idx = Enum.find_index(fields_in_order, &(&1 == :status))
      name_idx = Enum.find_index(fields_in_order, &(&1 == :name))
      email_idx = Enum.find_index(fields_in_order, &(&1 == :email))

      assert status_idx < name_idx
      assert name_idx < email_idx
    end

    test "required errors come before format errors" do
      cs =
        changeset(%{email: "bad"})
        |> Ecto.Changeset.add_error(:email, "bad format", validation: :format)
        |> Ecto.Changeset.validate_required([:name])

      prioritized = Errors.prioritize(cs)
      validations = Enum.map(prioritized, fn {_, {_, opts}} -> Keyword.get(opts, :validation) end)

      required_idx = Enum.find_index(validations, &(&1 == :required))
      format_idx = Enum.find_index(validations, &(&1 == :format))

      assert required_idx < format_idx
    end

    test "custom errors come last" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:email, "custom issue", validation: :custom)

      prioritized = Errors.prioritize(cs)
      validations = Enum.map(prioritized, fn {_, {_, opts}} -> Keyword.get(opts, :validation) end)

      required_idx = Enum.find_index(validations, &(&1 == :required))
      custom_idx = Enum.find_index(validations, &(&1 == :custom))

      assert required_idx < custom_idx
    end

    test "errors without validation key get lowest priority" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:email, "unknown error")

      prioritized = Errors.prioritize(cs)

      # required should come first
      {first_field, _} = hd(prioritized)
      assert first_field == :name
    end
  end

  # ============================================
  # group_by_priority/1
  # ============================================

  describe "group_by_priority/1" do
    test "returns map with :high, :medium, :low keys" do
      result = Errors.group_by_priority(changeset(%{}))

      assert Map.has_key?(result, :high)
      assert Map.has_key?(result, :medium)
      assert Map.has_key?(result, :low)
    end

    test "groups required errors as :high" do
      cs = changeset_with_required_error()
      result = Errors.group_by_priority(cs)

      assert length(result.high) == 1
      assert result.medium == []
      assert result.low == []
    end

    test "groups format errors as :medium" do
      cs = changeset_with_format_error()
      result = Errors.group_by_priority(cs)

      assert result.high == []
      assert length(result.medium) == 1
      assert result.low == []
    end

    test "groups length errors as :medium" do
      cs = changeset_with_length_error()
      result = Errors.group_by_priority(cs)

      assert result.high == []
      assert length(result.medium) == 1
    end

    test "groups unique errors as :low" do
      cs = changeset_with_unique_error()
      result = Errors.group_by_priority(cs)

      assert result.high == []
      assert result.medium == []
      assert length(result.low) == 1
    end

    test "groups custom errors as :low" do
      cs = changeset_with_custom_error()
      result = Errors.group_by_priority(cs)

      assert result.high == []
      assert result.medium == []
      assert length(result.low) == 1
    end

    test "groups type errors as :high" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.add_error(:age, "is invalid", validation: :type)

      result = Errors.group_by_priority(cs)

      assert length(result.high) == 1
    end

    test "groups acceptance errors as :medium" do
      cs = changeset_with_acceptance_error()
      result = Errors.group_by_priority(cs)

      assert length(result.medium) == 1
    end

    test "distributes mixed errors into correct groups" do
      cs =
        changeset(%{name: "ab"})
        |> Ecto.Changeset.validate_required([:email])
        |> Ecto.Changeset.validate_length(:name, min: 3)
        |> Ecto.Changeset.add_error(:code, "taken", validation: :unique)

      result = Errors.group_by_priority(cs)

      assert length(result.high) == 1
      assert length(result.medium) == 1
      assert length(result.low) == 1
    end

    test "returns empty lists when no errors" do
      cs = changeset(%{name: "test"})
      result = Errors.group_by_priority(cs)

      assert result.high == []
      assert result.medium == []
      assert result.low == []
    end
  end

  # ============================================
  # highest_priority_per_field/1
  # ============================================

  describe "highest_priority_per_field/1" do
    test "returns one error per field" do
      cs =
        changeset(%{name: "ab"})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.validate_length(:name, min: 5)

      result = Errors.highest_priority_per_field(cs)
      fields = Enum.map(result, fn {field, _} -> field end)

      # Only one error for :name (the required one, higher priority)
      assert length(fields) == length(Enum.uniq(fields))
    end

    test "picks the highest priority error for each field" do
      # Add a required error and a custom error both on :name
      cs =
        changeset(%{})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:name, "custom issue", validation: :custom)

      result = Errors.highest_priority_per_field(cs)

      # Should only have one error for name, the required one
      name_errors = Enum.filter(result, fn {field, _} -> field == :name end)
      assert length(name_errors) == 1

      {_field, {_msg, opts}} = hd(name_errors)
      assert Keyword.get(opts, :validation) == :required
    end

    test "returns empty list for valid changeset" do
      assert Errors.highest_priority_per_field(changeset(%{name: "ok"})) == []
    end

    test "handles multiple fields each with their highest priority" do
      cs =
        changeset(%{email: "bad"})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:email, "taken", validation: :unique)

      result = Errors.highest_priority_per_field(cs)
      assert length(result) == 2

      fields_map = Map.new(result, fn {field, {_, opts}} -> {field, Keyword.get(opts, :validation)} end)
      assert fields_map[:name] == :required
      assert fields_map[:email] == :unique
    end
  end

  # ============================================
  # to_simple_map/1
  # ============================================

  describe "to_simple_map/1" do
    test "returns empty map for valid changeset" do
      assert Errors.to_simple_map(changeset(%{name: "test"})) == %{}
    end

    test "returns field => messages map" do
      cs = changeset_with_required_error()
      result = Errors.to_simple_map(cs)

      assert is_map(result)
      assert Map.has_key?(result, :name)
      assert is_list(result[:name])
      assert length(result[:name]) > 0
    end

    test "interpolates error message variables" do
      cs =
        changeset(%{name: "ab"})
        |> Ecto.Changeset.validate_length(:name, min: 3)

      result = Errors.to_simple_map(cs)
      [message] = result[:name]

      # The message should have the count interpolated
      assert is_binary(message)
      assert String.contains?(message, "3")
    end

    test "groups multiple errors per field" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:name, "is too boring")

      result = Errors.to_simple_map(cs)
      assert length(result[:name]) == 2
    end
  end

  # ============================================
  # to_flat_list/1
  # ============================================

  describe "to_flat_list/1" do
    test "returns empty list for valid changeset" do
      assert Errors.to_flat_list(changeset(%{name: "test"})) == []
    end

    test "returns list of formatted messages" do
      cs = changeset_with_required_error()
      result = Errors.to_flat_list(cs)

      assert is_list(result)
      assert length(result) > 0

      [message | _] = result
      assert is_binary(message)
      # Should contain humanized field name
      assert String.contains?(message, "Name")
    end

    test "humanizes field names (replaces underscores and capitalizes)" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.add_error(:status, "is required", validation: :required)

      [message] = Errors.to_flat_list(cs)
      assert String.starts_with?(message, "Status:")
    end

    test "includes multiple errors from multiple fields" do
      cs = changeset_with_multiple_errors()
      result = Errors.to_flat_list(cs)

      assert length(result) >= 3
    end
  end

  # ============================================
  # to_message/1
  # ============================================

  describe "to_message/1" do
    test "returns 'No errors' for valid changeset" do
      assert Errors.to_message(changeset(%{name: "test"})) == "No errors"
    end

    test "returns single error directly" do
      cs = changeset_with_required_error()
      result = Errors.to_message(cs)

      assert is_binary(result)
      assert String.contains?(result, "Name")
      refute String.contains?(result, "Multiple")
    end

    test "formats multiple errors with bullet points" do
      cs = changeset_with_multiple_errors()
      result = Errors.to_message(cs)

      assert String.starts_with?(result, "Multiple validation errors:")
      assert String.contains?(result, "\n")
    end
  end

  # ============================================
  # for_field/2
  # ============================================

  describe "for_field/2" do
    test "returns messages for a specific field" do
      cs = changeset_with_required_error()
      result = Errors.for_field(cs, :name)

      assert is_list(result)
      assert length(result) > 0
    end

    test "returns empty list for field with no errors" do
      cs = changeset_with_required_error()
      assert Errors.for_field(cs, :email) == []
    end

    test "returns empty list for valid changeset" do
      cs = changeset(%{name: "test"})
      assert Errors.for_field(cs, :name) == []
    end
  end

  # ============================================
  # has_error?/3
  # ============================================

  describe "has_error?/3 with validation type atom" do
    test "returns true when validation type matches" do
      cs = changeset_with_required_error()
      assert Errors.has_error?(cs, :name, :required)
    end

    test "returns false when validation type does not match" do
      cs = changeset_with_required_error()
      refute Errors.has_error?(cs, :name, :format)
    end

    test "returns false for field without errors" do
      cs = changeset_with_required_error()
      refute Errors.has_error?(cs, :email, :required)
    end

    test "matches specific validation types" do
      cs = changeset_with_length_error()
      assert Errors.has_error?(cs, :name, :length)
    end

    test "returns false for valid changeset" do
      cs = changeset(%{name: "test"})
      refute Errors.has_error?(cs, :name, :required)
    end
  end

  describe "has_error?/3 with message string" do
    test "returns true when message matches" do
      cs = changeset_with_custom_error()
      assert Errors.has_error?(cs, :name, "custom validation failed")
    end

    test "returns false when message does not match" do
      cs = changeset_with_custom_error()
      refute Errors.has_error?(cs, :name, "different message")
    end

    test "returns false for field without errors" do
      cs = changeset_with_custom_error()
      refute Errors.has_error?(cs, :email, "custom validation failed")
    end
  end

  # ============================================
  # count_errors/1
  # ============================================

  describe "count_errors/1" do
    test "returns 0 for valid changeset" do
      assert Errors.count_errors(changeset(%{name: "test"})) == 0
    end

    test "counts single error" do
      cs = changeset_with_required_error()
      assert Errors.count_errors(cs) == 1
    end

    test "counts multiple errors" do
      cs = changeset_with_multiple_errors()
      assert Errors.count_errors(cs) >= 3
    end

    test "counts duplicate field errors separately" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:name, "too boring")

      assert Errors.count_errors(cs) == 2
    end
  end

  # ============================================
  # count_fields_with_errors/1
  # ============================================

  describe "count_fields_with_errors/1" do
    test "returns 0 for valid changeset" do
      assert Errors.count_fields_with_errors(changeset(%{name: "test"})) == 0
    end

    test "counts unique fields with errors" do
      cs = changeset_with_multiple_errors()
      # status (required), name (length), email (format)
      assert Errors.count_fields_with_errors(cs) == 3
    end

    test "counts field once even with multiple errors" do
      cs =
        changeset(%{})
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.add_error(:name, "too boring")

      assert Errors.count_fields_with_errors(cs) == 1
    end
  end

  # ============================================
  # merge/1
  # ============================================

  describe "merge/1" do
    test "merges errors from multiple changesets" do
      cs1 = changeset_with_required_error()
      cs2 = changeset_with_format_error()

      result = Errors.merge([cs1, cs2])

      assert is_list(result)
      fields = Enum.map(result, fn {field, _} -> field end)
      assert :name in fields
      assert :email in fields
    end

    test "deduplicates identical errors" do
      cs1 = changeset_with_required_error()
      cs2 = changeset_with_required_error()

      result = Errors.merge([cs1, cs2])

      # Same error should appear only once
      name_errors = Enum.filter(result, fn {field, _} -> field == :name end)
      assert length(name_errors) == 1
    end

    test "returns empty list when all changesets are valid" do
      cs1 = changeset(%{name: "test"})
      cs2 = changeset(%{email: "ok"})

      assert Errors.merge([cs1, cs2]) == []
    end

    test "handles single changeset" do
      cs = changeset_with_required_error()
      result = Errors.merge([cs])

      assert length(result) == 1
    end

    test "handles empty list" do
      assert Errors.merge([]) == []
    end
  end

  # ============================================
  # clear_fields/2
  # ============================================

  describe "clear_fields/2" do
    test "removes errors for specified fields" do
      cs = changeset_with_multiple_errors()
      result = Errors.clear_fields(cs, [:name, :email])

      remaining_fields = Enum.map(result.errors, fn {field, _} -> field end)
      refute :name in remaining_fields
      refute :email in remaining_fields
    end

    test "keeps errors for other fields" do
      cs = changeset_with_multiple_errors()
      result = Errors.clear_fields(cs, [:name])

      remaining_fields = Enum.map(result.errors, fn {field, _} -> field end)
      refute :name in remaining_fields
      # Other fields should still have errors
      assert length(result.errors) > 0
    end

    test "sets valid? to true when all errors cleared" do
      cs = changeset_with_required_error()
      result = Errors.clear_fields(cs, [:name])

      assert result.valid?
      assert result.errors == []
    end

    test "sets valid? to false when errors remain" do
      cs = changeset_with_multiple_errors()
      result = Errors.clear_fields(cs, [:name])

      refute result.valid?
    end

    test "handles clearing non-existent field" do
      cs = changeset_with_required_error()
      result = Errors.clear_fields(cs, [:nonexistent])

      # Original errors unchanged
      assert length(result.errors) == 1
    end

    test "handles empty fields list" do
      cs = changeset_with_required_error()
      result = Errors.clear_fields(cs, [])

      assert result.errors == cs.errors
    end
  end

  # ============================================
  # add_context/2
  # ============================================

  describe "add_context/2" do
    test "prepends context to error messages" do
      cs = changeset_with_required_error()
      result = Errors.add_context(cs, "Registration")

      [{:name, {msg, _opts}}] = result.errors
      assert String.starts_with?(msg, "Registration: ")
    end

    test "preserves error options" do
      cs = changeset_with_required_error()
      result = Errors.add_context(cs, "Step 1")

      [{:name, {_msg, opts}}] = result.errors
      assert Keyword.get(opts, :validation) == :required
    end

    test "adds context to all errors" do
      cs = changeset_with_multiple_errors()
      result = Errors.add_context(cs, "Form")

      Enum.each(result.errors, fn {_field, {msg, _opts}} ->
        assert String.starts_with?(msg, "Form: ")
      end)
    end

    test "handles empty context string" do
      cs = changeset_with_required_error()
      result = Errors.add_context(cs, "")

      [{:name, {msg, _opts}}] = result.errors
      assert String.starts_with?(msg, ": ")
    end

    test "does not change error count" do
      cs = changeset_with_multiple_errors()
      result = Errors.add_context(cs, "Test")

      assert length(result.errors) == length(cs.errors)
    end
  end
end
