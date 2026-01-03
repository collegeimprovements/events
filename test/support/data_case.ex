defmodule Events.DataCase do
  @moduledoc """
  Test case for tests requiring database access.

  ## When to Use

  Use `Events.DataCase` for:
  - Context modules that interact with the database
  - Schema tests with persistence
  - Repository operations
  - Database constraints and validations

  For pure unit tests, use `Events.TestCase` instead.
  For Phoenix controller tests, use `EventsWeb.ConnCase`.

  ## Usage

      defmodule Events.AccountsTest do
        use Events.DataCase, async: true

        test "creates user with valid attrs" do
          attrs = build(:user)
          assert {:ok, user} = Accounts.create_user(attrs)
          assert user.email == attrs.email
        end
      end

  ## Features

  - Database sandbox (automatic transaction rollback)
  - Ecto imports (`Ecto`, `Ecto.Query`, `Ecto.Changeset`)
  - Custom assertions (`assert_ok`, `assert_error`, `assert_valid`)
  - Test factory (`build/2`, `build_list/3`)
  - Changeset helpers (`errors_on/1`)

  ## Test Tags

      @tag :slow        # Tests taking > 1 second
      @tag :integration # Full integration tests
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Events.Data.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Events.DataCase

      # Mocking support
      use Mimic

      # Custom assertions
      use Events.Test.Assertions

      # Test data factory
      import Events.Test.Factory

      # Property-based testing
      use ExUnitProperties
    end
  end

  setup tags do
    Events.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Events.Data.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Asserts that the given changeset has no errors.
  """
  def assert_changeset_valid(changeset) do
    assert changeset.valid?,
           "Expected changeset to be valid, got errors: #{inspect(errors_on(changeset))}"

    changeset
  end

  @doc """
  Asserts that the given changeset has errors.
  """
  def assert_changeset_invalid(changeset) do
    refute changeset.valid?, "Expected changeset to be invalid, but it was valid"
    changeset
  end

  @doc """
  Asserts a specific error exists on a field.
  """
  def assert_error_on(changeset, field, message \\ nil) do
    errors = errors_on(changeset)

    assert Map.has_key?(errors, field),
           "Expected error on :#{field}, got errors on: #{inspect(Map.keys(errors))}"

    if message do
      field_errors = Map.get(errors, field, [])

      assert message in field_errors,
             "Expected error '#{message}' on :#{field}, got: #{inspect(field_errors)}"
    end

    changeset
  end
end
