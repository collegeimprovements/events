defmodule Events.NormalizableTest do
  use ExUnit.Case, async: true

  alias Events.Error
  alias Events.Normalizable
  alias Events.HttpError
  alias Events.PosixError

  describe "Ecto.Changeset normalization" do
    test "normalizes invalid changeset to validation error" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [
          email: {"has invalid format", [validation: :format]},
          age:
            {"must be greater than %{number}",
             [validation: :number, kind: :greater_than, number: 0]}
        ],
        data: %{},
        changes: %{}
      }

      error = Normalizable.normalize(changeset)

      assert %Error{} = error
      assert error.type == :validation
      assert error.code == :changeset_invalid
      assert error.message == "Validation failed"
      assert error.source == Ecto.Changeset
      assert is_map(error.details.errors)
    end

    test "normalizes valid changeset to internal error" do
      changeset = %Ecto.Changeset{valid?: true, errors: [], data: %{}, changes: %{}}

      error = Normalizable.normalize(changeset)

      assert error.type == :internal
      assert error.code == :invalid_normalization
    end

    test "accepts context option" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [name: {"can't be blank", [validation: :required]}],
        data: %{},
        changes: %{}
      }

      error = Normalizable.normalize(changeset, context: %{user_id: 123})

      assert error.context.user_id == 123
    end
  end

  describe "Ecto exceptions normalization" do
    test "normalizes Ecto.NoResultsError to not_found" do
      exception = %Ecto.NoResultsError{message: "expected at least one result"}

      error = Normalizable.normalize(exception)

      assert error.type == :not_found
      assert error.code == :no_results
      assert error.source == Ecto.NoResultsError
    end

    test "normalizes Ecto.MultipleResultsError to conflict" do
      # Ecto.MultipleResultsError is raised by Ecto, we can create one via raise/rescue
      exception =
        try do
          raise Ecto.MultipleResultsError, queryable: "users", count: 3
        rescue
          e -> e
        end

      error = Normalizable.normalize(exception)

      assert error.type == :conflict
      assert error.code == :multiple_results
      assert error.source == Ecto.MultipleResultsError
    end

    test "normalizes Ecto.StaleEntryError as recoverable" do
      exception = %Ecto.StaleEntryError{message: "stale entry"}

      error = Normalizable.normalize(exception)

      assert error.type == :conflict
      assert error.code == :stale_entry
      assert error.recoverable == true
    end
  end

  describe "Postgrex.Error normalization" do
    test "normalizes unique violation" do
      exception = %Postgrex.Error{
        postgres: %{
          code: "23505",
          constraint: "users_email_index",
          message: "duplicate key value"
        }
      }

      error = Normalizable.normalize(exception)

      assert error.type == :conflict
      assert error.code == :unique_violation
      assert error.source == Postgrex
      assert error.details.postgres_code == "23505"
      assert error.details.constraint == "users_email_index"
    end

    test "normalizes foreign key violation" do
      exception = %Postgrex.Error{
        postgres: %{
          code: "23503",
          constraint: "posts_user_id_fkey"
        }
      }

      error = Normalizable.normalize(exception)

      assert error.type == :unprocessable
      assert error.code == :foreign_key_violation
    end

    test "normalizes serialization failure as recoverable" do
      exception = %Postgrex.Error{
        postgres: %{code: "40001"}
      }

      error = Normalizable.normalize(exception)

      assert error.type == :conflict
      assert error.code == :serialization_failure
      assert error.recoverable == true
    end

    test "normalizes connection error as recoverable" do
      exception = %Postgrex.Error{
        postgres: %{code: "08006"}
      }

      error = Normalizable.normalize(exception)

      assert error.type == :network
      assert error.code == :connection_failure
      assert error.recoverable == true
    end
  end

  describe "DBConnection.ConnectionError normalization" do
    test "normalizes pool exhausted error" do
      exception = %DBConnection.ConnectionError{
        message: "connection not available and request was dropped from queue",
        severity: :error,
        reason: :queue_timeout
      }

      error = Normalizable.normalize(exception)

      assert error.type == :external
      assert error.code == :pool_exhausted
      assert error.recoverable == true
    end

    test "normalizes timeout error" do
      exception = %DBConnection.ConnectionError{
        message: "connection timed out",
        severity: :error,
        reason: :timeout
      }

      error = Normalizable.normalize(exception)

      assert error.type == :timeout
      assert error.code == :connection_timeout
      assert error.recoverable == true
    end
  end

  describe "Mint.TransportError normalization" do
    test "normalizes timeout" do
      exception = %Mint.TransportError{reason: :timeout}

      error = Normalizable.normalize(exception)

      assert error.type == :timeout
      assert error.code == :connection_timeout
      assert error.recoverable == true
    end

    test "normalizes connection refused" do
      exception = %Mint.TransportError{reason: :econnrefused}

      error = Normalizable.normalize(exception)

      assert error.type == :network
      assert error.code == :connection_refused
      assert error.recoverable == true
    end

    test "normalizes DNS error" do
      exception = %Mint.TransportError{reason: :nxdomain}

      error = Normalizable.normalize(exception)

      assert error.type == :network
      assert error.code == :dns_error
      # Note: recoverable is inferred as true for :network type by Error.new
      # even though DNS "domain not found" is not truly recoverable
      assert error.recoverable == true
    end

    test "normalizes TLS error" do
      exception = %Mint.TransportError{
        reason: {:tls_alert, {:certificate_expired, "certificate expired"}}
      }

      error = Normalizable.normalize(exception)

      assert error.type == :network
      assert error.code == :certificate_expired
      # Note: recoverable is inferred as true for :network type by Error.new
      assert error.recoverable == true
    end
  end

  describe "Mint.HTTPError normalization" do
    test "normalizes HTTP protocol error" do
      exception = %Mint.HTTPError{reason: :invalid_response, module: Mint.HTTP1}

      error = Normalizable.normalize(exception)

      assert error.type == :external
      assert error.code == :invalid_response
    end

    test "normalizes too many requests as recoverable" do
      exception = %Mint.HTTPError{reason: :too_many_concurrent_requests, module: Mint.HTTP2}

      error = Normalizable.normalize(exception)

      assert error.type == :external
      assert error.code == :too_many_requests
      assert error.recoverable == true
    end
  end

  describe "HttpError wrapper normalization" do
    test "normalizes 404 to not_found" do
      http_error = HttpError.new(404)

      error = Normalizable.normalize(http_error)

      assert error.type == :not_found
      assert error.code == :not_found
      assert error.recoverable == false
      assert error.details.status_code == 404
    end

    test "normalizes 500 as recoverable" do
      http_error = HttpError.new(500, body: %{"error" => "internal error"})

      error = Normalizable.normalize(http_error)

      assert error.type == :external
      assert error.code == :internal_server_error
      assert error.recoverable == true
    end

    test "normalizes 429 as rate limited" do
      http_error = HttpError.new(429, url: "https://api.example.com/users")

      error = Normalizable.normalize(http_error)

      assert error.type == :rate_limited
      assert error.code == :too_many_requests
      assert error.recoverable == true
      assert error.details.url == "https://api.example.com/users"
    end

    test "normalizes 401 to unauthorized" do
      http_error = HttpError.new(401)

      error = Normalizable.normalize(http_error)

      assert error.type == :unauthorized
      assert error.code == :unauthorized
    end

    test "normalizes 403 to forbidden" do
      http_error = HttpError.new(403)

      error = Normalizable.normalize(http_error)

      assert error.type == :forbidden
      assert error.code == :forbidden
    end
  end

  describe "PosixError wrapper normalization" do
    test "normalizes :enoent to not_found" do
      posix_error = PosixError.new(:enoent, path: "/path/to/file")

      error = Normalizable.normalize(posix_error)

      assert error.type == :not_found
      assert error.code == :file_not_found
      assert error.message =~ "/path/to/file"
      assert error.details.path == "/path/to/file"
    end

    test "normalizes :eacces to forbidden" do
      posix_error = PosixError.new(:eacces, path: "/etc/passwd", operation: :write)

      error = Normalizable.normalize(posix_error)

      assert error.type == :forbidden
      assert error.code == :permission_denied
      assert error.details.operation == :write
    end

    test "normalizes :enospc as recoverable" do
      posix_error = PosixError.new(:enospc)

      error = Normalizable.normalize(posix_error)

      assert error.type == :external
      assert error.code == :disk_full
      assert error.recoverable == true
    end
  end

  describe "atom normalization (via Any fallback)" do
    test "normalizes :not_found" do
      error = Normalizable.normalize(:not_found)

      assert error.type == :not_found
      assert error.code == :not_found
    end

    test "normalizes :unauthorized" do
      error = Normalizable.normalize(:unauthorized)

      assert error.type == :unauthorized
      assert error.code == :unauthorized
    end

    test "normalizes :timeout as recoverable" do
      error = Normalizable.normalize(:timeout)

      assert error.type == :timeout
      assert error.code == :timeout
      assert error.recoverable == true
    end

    test "normalizes unknown atoms" do
      error = Normalizable.normalize(:some_custom_error)

      assert error.type == :internal
      assert error.code == :some_custom_error
    end
  end

  describe "string normalization (via Any fallback)" do
    test "normalizes string message" do
      error = Normalizable.normalize("Something went wrong")

      assert error.type == :internal
      assert error.code == :string_error
      assert error.message == "Something went wrong"
    end
  end

  describe "exception normalization (via Any fallback)" do
    test "normalizes RuntimeError" do
      exception = %RuntimeError{message: "oops"}

      error = Normalizable.normalize(exception)

      assert error.type == :internal
      assert error.code == :runtime_error
      assert error.message == "oops"
      assert error.source == RuntimeError
    end

    test "normalizes ArgumentError to validation" do
      exception = %ArgumentError{message: "bad argument"}

      error = Normalizable.normalize(exception)

      assert error.type == :validation
      assert error.code == :argument_error
    end

    test "attaches stacktrace when provided" do
      exception = %RuntimeError{message: "boom"}
      stacktrace = [{__MODULE__, :test, 0, [file: ~c"test.ex", line: 1]}]

      error = Normalizable.normalize(exception, stacktrace: stacktrace)

      assert error.stacktrace == stacktrace
    end
  end

  describe "Events.Error passthrough" do
    test "already normalized errors are passed through" do
      original = Error.new(:validation, :test_error, message: "test")

      error = Normalizable.normalize(original)

      assert error == original
    end

    test "context is merged into already normalized errors" do
      original = Error.new(:validation, :test_error, context: %{existing: true})

      error = Normalizable.normalize(original, context: %{new: true})

      assert error.context.existing == true
      assert error.context.new == true
    end

    test "step is added if not present" do
      original = Error.new(:validation, :test_error)

      error = Normalizable.normalize(original, step: :my_step)

      assert error.step == :my_step
    end

    test "existing step is not overwritten" do
      original = Error.new(:validation, :test_error, step: :original_step)

      error = Normalizable.normalize(original, step: :new_step)

      assert error.step == :original_step
    end
  end

  describe "map normalization (via Any fallback)" do
    test "normalizes map with message and code" do
      map = %{message: "Custom error", code: :custom_code, extra: "data"}

      error = Normalizable.normalize(map)

      assert error.type == :internal
      assert error.code == :custom_code
      assert error.message == "Custom error"
      assert error.details.extra == "data"
    end

    test "normalizes map with string keys" do
      map = %{"message" => "Error message", "code" => "error_code"}

      error = Normalizable.normalize(map)

      assert error.message == "Error message"
      assert error.code == :error_code
    end
  end

  describe "@derive support" do
    # NOTE: @derive for protocols only works before protocol consolidation.
    # In tests, the protocol is already consolidated, so derived implementations
    # fall back to the Any implementation. To test @derive, you would need to
    # either disable consolidation in test or define the struct before compilation.
    #
    # This test verifies that the Any fallback handles unknown structs gracefully.

    defmodule DerivedError do
      # This derive won't take effect because protocol is already consolidated
      @derive {Events.Normalizable, type: :business, code: :derived_error, recoverable: true}
      defstruct [:message, :details]
    end

    @tag :skip
    test "derived implementation works (only before consolidation)" do
      custom_error = %DerivedError{message: "Derived error message", details: %{foo: "bar"}}

      error = Normalizable.normalize(custom_error)

      assert error.type == :business
      assert error.code == :derived_error
      assert error.message == "Derived error message"
      assert error.details == %{foo: "bar"}
      assert error.recoverable == true
    end

    test "Any fallback handles unknown struct when derived is not available" do
      custom_error = %DerivedError{message: "Derived error message", details: %{foo: "bar"}}

      error = Normalizable.normalize(custom_error)

      # Falls back to Any implementation since protocol is consolidated
      assert %Error{} = error
      assert error.type == :internal
      assert error.message == "Derived error message"
    end
  end

  describe "integration with Normalizer" do
    alias Events.Errors.Normalizer

    test "Normalizer delegates to protocol" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [name: {"is required", [validation: :required]}],
        data: %{},
        changes: %{}
      }

      error = Normalizer.normalize(changeset)

      assert error.type == :validation
      assert error.code == :changeset_invalid
    end

    test "Normalizer unwraps error tuples" do
      error = Normalizer.normalize({:error, :not_found})

      assert error.type == :not_found
      assert error.code == :not_found
    end

    test "normalize_result passes ok values through" do
      result = Normalizer.normalize_result({:ok, "value"})

      assert result == {:ok, "value"}
    end

    test "normalize_result normalizes error values" do
      result = Normalizer.normalize_result({:error, :not_found})

      assert {:error, %Error{type: :not_found}} = result
    end

    test "wrap catches and normalizes exceptions" do
      result = Normalizer.wrap(fn -> raise "boom" end)

      assert {:error, %Error{type: :internal, code: :runtime_error}} = result
    end
  end
end
