defmodule OmCrud.ErrorTest do
  @moduledoc """
  Tests for OmCrud.Error - Rich error types for CRUD operations.

  Provides structured error information with context about what went wrong,
  including operation type, schema, field-level details, and original errors.

  ## Use Cases

  - **Not found errors**: Clear indication of missing records with schema/id
  - **Validation errors**: Field-level error messages from changesets
  - **Constraint violations**: Database constraint errors with context
  - **Step failures**: Errors in atomic operations with step names
  - **HTTP responses**: Error-to-HTTP-status mapping for APIs
  """

  use ExUnit.Case, async: true

  alias OmCrud.Error

  defmodule TestSchema do
    use Ecto.Schema

    schema "test_schemas" do
      field :name, :string
      field :email, :string
    end

    def changeset(struct, attrs) do
      Ecto.Changeset.cast(struct, attrs, [:name, :email])
    end
  end

  describe "not_found/3" do
    test "creates a not_found error" do
      error = Error.not_found(TestSchema, "123")

      assert %Error{} = error
      assert error.type == :not_found
      assert error.schema == TestSchema
      assert error.id == "123"
      assert error.operation == :fetch
    end

    test "accepts custom operation" do
      error = Error.not_found(TestSchema, "123", operation: :update)

      assert error.operation == :update
    end

    test "accepts metadata" do
      error = Error.not_found(TestSchema, "123", metadata: %{tenant: "acme"})

      assert error.metadata == %{tenant: "acme"}
    end
  end

  describe "from_changeset/2" do
    test "creates error from invalid changeset" do
      changeset =
        %TestSchema{}
        |> Ecto.Changeset.cast(%{}, [:name, :email])
        |> Ecto.Changeset.add_error(:email, "is required")

      error = Error.from_changeset(changeset)

      assert %Error{} = error
      assert error.type == :validation_error
      assert error.schema == TestSchema
      assert error.changeset == changeset
      assert error.errors == [{:email, {"is required", []}}]
    end

    test "detects constraint violations" do
      changeset =
        %TestSchema{}
        |> Ecto.Changeset.cast(%{email: "test@example.com"}, [:email])
        |> Ecto.Changeset.add_error(:email, "has already been taken",
          constraint: :unique,
          constraint_name: "users_email_index"
        )

      error = Error.from_changeset(changeset)

      assert error.type == :constraint_violation
      assert error.constraint == "users_email_index"
    end
  end

  describe "constraint_violation/3" do
    test "creates a constraint violation error" do
      error = Error.constraint_violation(:users_email_unique, TestSchema)

      assert %Error{} = error
      assert error.type == :constraint_violation
      assert error.constraint == :users_email_unique
      assert error.schema == TestSchema
    end

    test "accepts field and value" do
      error = Error.constraint_violation(:users_email_unique, TestSchema,
        field: :email,
        value: "test@example.com"
      )

      assert error.field == :email
      assert error.value == "test@example.com"
    end
  end

  describe "validation_error/3" do
    test "creates a validation error" do
      error = Error.validation_error(:email, "is invalid")

      assert %Error{} = error
      assert error.type == :validation_error
      assert error.field == :email
      assert error.message == "is invalid"
      assert error.errors == [{:email, {"is invalid", []}}]
    end

    test "accepts schema and operation" do
      error = Error.validation_error(:email, "is invalid", schema: TestSchema, operation: :create)

      assert error.schema == TestSchema
      assert error.operation == :create
    end
  end

  describe "step_failed/3" do
    test "creates a step_failed error" do
      error = Error.step_failed(:create_user, {:error, :invalid})

      assert %Error{} = error
      assert error.type == :step_failed
      assert error.step == :create_user
      assert error.original == {:error, :invalid}
    end

    test "extracts details from changeset error" do
      changeset =
        %TestSchema{}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.add_error(:name, "can't be blank")

      error = Error.step_failed(:create_user, {:error, changeset})

      assert error.type == :step_failed
      assert error.step == :create_user
      assert error.schema == TestSchema
      assert error.changeset == changeset
      assert error.errors == [{:name, {"can't be blank", []}}]
    end

    test "extracts details from nested Error" do
      inner_error = Error.not_found(TestSchema, "123")
      error = Error.step_failed(:fetch_user, {:error, inner_error})

      assert error.step == :fetch_user
      assert error.original == inner_error
      assert error.schema == TestSchema
    end
  end

  describe "transaction_error/2" do
    test "creates a transaction error" do
      error = Error.transaction_error(:rollback)

      assert %Error{} = error
      assert error.type == :transaction_error
      assert error.original == :rollback
      assert error.operation == :transaction
    end

    test "accepts step name" do
      error = Error.transaction_error(:timeout, step: :slow_operation)

      assert error.step == :slow_operation
    end
  end

  describe "stale_entry/3" do
    test "creates a stale entry error" do
      error = Error.stale_entry(TestSchema, "123")

      assert %Error{} = error
      assert error.type == :stale_entry
      assert error.schema == TestSchema
      assert error.id == "123"
      assert error.operation == :update
    end
  end

  describe "wrap/2" do
    test "returns Error unchanged" do
      original = Error.not_found(TestSchema, "123")
      wrapped = Error.wrap(original, [])

      assert wrapped == original
    end

    test "wraps changeset" do
      changeset =
        %TestSchema{}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.add_error(:name, "is required")

      wrapped = Error.wrap(changeset, [])

      assert wrapped.type == :validation_error
      assert wrapped.changeset == changeset
    end

    test "wraps arbitrary error" do
      wrapped = Error.wrap(:some_error, operation: :custom)

      assert wrapped.type == :unknown
      assert wrapped.original == :some_error
      assert wrapped.operation == :custom
    end
  end

  describe "message/1" do
    test "generates message for not_found" do
      error = Error.not_found(TestSchema, "123")

      assert Error.message(error) == "TestSchema with id \"123\" not found"
    end

    test "generates message for step_failed" do
      error = Error.step_failed(:create_user, {:error, :invalid})

      assert Error.message(error) =~ "Step :create_user failed"
    end

    test "generates message for stale_entry" do
      error = Error.stale_entry(TestSchema, "123")

      assert Error.message(error) =~ "has been modified by another process"
    end

    test "uses custom message if set" do
      error = %Error{type: :custom, message: "Custom error message"}

      assert Error.message(error) == "Custom error message"
    end
  end

  describe "to_map/1" do
    test "converts error to map" do
      error = Error.not_found(TestSchema, "123")
      map = Error.to_map(error)

      assert map.type == :not_found
      assert map.schema == "TestSchema"
      assert map.id == "123"
      assert map.message =~ "not found"
    end

    test "excludes nil fields" do
      error = Error.validation_error(:email, "is invalid")
      map = Error.to_map(error)

      refute Map.has_key?(map, :id)
      refute Map.has_key?(map, :constraint)
    end
  end

  describe "to_http_status/1" do
    test "returns 404 for not_found" do
      error = Error.not_found(TestSchema, "123")

      assert Error.to_http_status(error) == 404
    end

    test "returns 422 for validation_error" do
      error = Error.validation_error(:email, "is invalid")

      assert Error.to_http_status(error) == 422
    end

    test "returns 409 for constraint_violation" do
      error = Error.constraint_violation(:unique, TestSchema)

      assert Error.to_http_status(error) == 409
    end

    test "returns 409 for stale_entry" do
      error = Error.stale_entry(TestSchema, "123")

      assert Error.to_http_status(error) == 409
    end

    test "returns 500 for unknown" do
      error = %Error{type: :unknown}

      assert Error.to_http_status(error) == 500
    end
  end

  describe "is_type?/2" do
    test "returns true when type matches" do
      error = Error.not_found(TestSchema, "123")

      assert Error.is_type?(error, :not_found) == true
      assert Error.is_type?(error, :validation_error) == false
    end
  end

  describe "on_field?/2" do
    test "returns true when field matches" do
      error = Error.validation_error(:email, "is invalid")

      assert Error.on_field?(error, :email) == true
      assert Error.on_field?(error, :name) == false
    end

    test "checks errors list" do
      changeset =
        %TestSchema{}
        |> Ecto.Changeset.cast(%{}, [:name, :email])
        |> Ecto.Changeset.add_error(:name, "is required")
        |> Ecto.Changeset.add_error(:email, "is invalid")

      error = Error.from_changeset(changeset)

      assert Error.on_field?(error, :name) == true
      assert Error.on_field?(error, :email) == true
      assert Error.on_field?(error, :other) == false
    end
  end

  describe "String.Chars implementation" do
    test "converts error to string" do
      error = Error.not_found(TestSchema, "123")

      assert to_string(error) == Error.message(error)
    end
  end
end
