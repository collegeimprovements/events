defmodule OmCrud.AtomicTest do
  @moduledoc """
  Tests for OmCrud.Atomic - Atomic operations helper.

  Provides a clean, functional approach to atomic operations with automatic
  error handling and rollback.

  ## Use Cases

  - **Multi-step operations**: Create user + account + settings atomically
  - **Clean error handling**: Using step!/1 for concise code
  - **Named steps**: Better error reporting with step names
  - **Context accumulation**: Building up state across steps
  """

  use ExUnit.Case, async: true

  alias OmCrud.Atomic
  alias OmCrud.Atomic.StepError, as: StepError
  alias OmCrud.Error

  defmodule ChangesetTestSchema do
    defstruct [:name]
  end

  describe "step!/1" do
    test "unwraps {:ok, value}" do
      result = Atomic.step!({:ok, :value})

      assert result == :value
    end

    test "raises StepError on {:error, reason}" do
      assert_raise StepError, fn ->
        Atomic.step!({:error, :some_error})
      end
    end

    test "raises StepError with wrapped Error" do
      error = Error.not_found(SomeSchema, "123")

      assert_raise StepError, fn ->
        Atomic.step!({:error, error})
      end
    end

    test "raises StepError with changeset error" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [{:name, {"is required", []}}],
        data: %ChangesetTestSchema{name: nil}
      }

      assert_raise StepError, fn ->
        Atomic.step!({:error, changeset})
      end
    end
  end

  describe "step!/2 with named step" do
    test "unwraps {:ok, value}" do
      result = Atomic.step!(:fetch_user, {:ok, :user})

      assert result == :user
    end

    test "raises StepError with step name" do
      try do
        Atomic.step!(:create_user, {:error, :validation_failed})
        flunk("Expected StepError")
      rescue
        e in StepError ->
          assert e.error.step == :create_user
      end
    end
  end

  describe "run_step/2" do
    test "returns {:ok, result} on success" do
      result = Atomic.run_step(:my_step, fn -> {:ok, :value} end)

      assert result == {:ok, :value}
    end

    test "returns {:error, Error} on failure" do
      result = Atomic.run_step(:my_step, fn -> {:error, :reason} end)

      assert {:error, %Error{}} = result
      assert elem(result, 1).step == :my_step
    end
  end

  describe "accumulate/3" do
    test "accumulates successful results" do
      context =
        %{}
        |> Atomic.accumulate(:first, fn -> {:ok, 1} end)
        |> Atomic.accumulate(:second, fn -> {:ok, 2} end)

      assert context == %{first: 1, second: 2}
    end

    test "passes context to function" do
      context =
        %{}
        |> Atomic.accumulate(:first, fn -> {:ok, 10} end)
        |> Atomic.accumulate(:second, fn ctx -> {:ok, ctx.first * 2} end)

      assert context == %{first: 10, second: 20}
    end

    test "raises StepError on failure" do
      assert_raise StepError, fn ->
        %{}
        |> Atomic.accumulate(:first, fn -> {:ok, 1} end)
        |> Atomic.accumulate(:failing, fn -> {:error, :fail} end)
      end
    end
  end

  describe "finalize/1" do
    test "wraps context in :ok tuple" do
      result = Atomic.finalize(%{user: :user_data, account: :account_data})

      assert result == {:ok, %{user: :user_data, account: :account_data}}
    end
  end

  describe "finalize/2" do
    test "extracts specific key" do
      result = Atomic.finalize(%{user: :user_data, account: :account_data}, :user)

      assert result == {:ok, :user_data}
    end

    test "raises on missing key" do
      assert_raise KeyError, fn ->
        Atomic.finalize(%{user: :user_data}, :missing_key)
      end
    end
  end

  describe "StepError" do
    test "has descriptive message" do
      error = Error.not_found(SomeSchema, "123")
      step_error = %StepError{error: error}

      message = Exception.message(step_error)

      assert message =~ "Atomic step failed"
    end
  end

  # ─────────────────────────────────────────────────────────────
  # New: Non-Raising step/2
  # ─────────────────────────────────────────────────────────────

  describe "step/2 (non-raising)" do
    test "returns {:ok, value} unchanged" do
      result = Atomic.step(:my_step, {:ok, :value})

      assert result == {:ok, :value}
    end

    test "wraps error with step context" do
      result = Atomic.step(:fetch_user, {:error, :not_found})

      assert {:error, %Error{type: :step_failed, step: :fetch_user}} = result
    end

    test "preserves original error in wrapped error" do
      result = Atomic.step(:create_user, {:error, :validation_failed})

      assert {:error, %Error{original: {:error, :validation_failed}}} = result
    end

    test "wraps OmCrud.Error with step context" do
      original_error = Error.not_found(SomeSchema, "123")
      result = Atomic.step(:fetch_user, {:error, original_error})

      assert {:error, %Error{type: :step_failed, step: :fetch_user, original: ^original_error}} =
               result
    end
  end

  # ─────────────────────────────────────────────────────────────
  # New: Optional Step Functions
  # ─────────────────────────────────────────────────────────────

  describe "optional_step!/2" do
    test "unwraps {:ok, value}" do
      result = Atomic.optional_step!(:fetch_org, {:ok, :org_data})

      assert result == :org_data
    end

    test "returns nil for {:error, :not_found}" do
      result = Atomic.optional_step!(:fetch_org, {:error, :not_found})

      assert result == nil
    end

    test "returns nil for {:error, %Error{type: :not_found}}" do
      error = Error.not_found(SomeSchema, "123")
      result = Atomic.optional_step!(:fetch_org, {:error, error})

      assert result == nil
    end

    test "raises StepError for non-not_found errors" do
      assert_raise StepError, fn ->
        Atomic.optional_step!(:fetch_org, {:error, :database_error})
      end
    end

    test "includes step name in raised error" do
      try do
        Atomic.optional_step!(:fetch_org, {:error, :connection_failed})
        flunk("Expected StepError")
      rescue
        e in StepError ->
          assert e.error.step == :fetch_org
      end
    end
  end

  # ─────────────────────────────────────────────────────────────
  # New: Accumulate Optional
  # ─────────────────────────────────────────────────────────────

  describe "accumulate_optional/3" do
    test "accumulates successful results" do
      context =
        %{}
        |> Atomic.accumulate_optional(:org, fn -> {:ok, :org_data} end)

      assert context == %{org: :org_data}
    end

    test "stores nil for :not_found" do
      context =
        %{}
        |> Atomic.accumulate_optional(:org, fn -> {:error, :not_found} end)

      assert context == %{org: nil}
    end

    test "stores nil for %Error{type: :not_found}" do
      error = Error.not_found(SomeSchema, "123")

      context =
        %{}
        |> Atomic.accumulate_optional(:org, fn -> {:error, error} end)

      assert context == %{org: nil}
    end

    test "passes context to function" do
      context =
        %{user_id: 42}
        |> Atomic.accumulate_optional(:profile, fn ctx -> {:ok, "profile_#{ctx.user_id}"} end)

      assert context == %{user_id: 42, profile: "profile_42"}
    end

    test "raises StepError on non-not_found errors" do
      assert_raise StepError, fn ->
        %{}
        |> Atomic.accumulate_optional(:org, fn -> {:error, :database_error} end)
      end
    end

    test "works with arity-0 functions" do
      context =
        %{existing: :data}
        |> Atomic.accumulate_optional(:optional, fn -> {:error, :not_found} end)

      assert context == %{existing: :data, optional: nil}
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Integration: Combined Optional + Required Steps
  # ─────────────────────────────────────────────────────────────

  describe "combined optional and required steps" do
    test "can mix accumulate and accumulate_optional" do
      context =
        %{}
        |> Atomic.accumulate(:user, fn -> {:ok, :user_data} end)
        |> Atomic.accumulate_optional(:org, fn -> {:error, :not_found} end)
        |> Atomic.accumulate(:settings, fn ctx -> {:ok, "settings_for_#{ctx.user}"} end)

      assert context == %{
               user: :user_data,
               org: nil,
               settings: "settings_for_user_data"
             }
    end

    test "optional step failure still propagates non-not_found errors" do
      assert_raise StepError, fn ->
        %{}
        |> Atomic.accumulate(:user, fn -> {:ok, :user_data} end)
        |> Atomic.accumulate_optional(:org, fn -> {:error, :timeout} end)
      end
    end
  end
end
