defmodule FnTypes.ResultTest do
  @moduledoc """
  Tests for FnTypes.Result - Functional error handling.

  Result is the foundational type for representing operations that can fail.
  Use it instead of raising exceptions or returning nil.

  ## When to Use Result

  - Database operations (fetch, insert, update)
  - API calls that may fail
  - Validation that can produce errors
  - Any fallible operation where you want explicit error handling

  ## Pattern: Railway-Oriented Programming

  Result enables "railway-oriented programming" where you chain operations
  and errors automatically short-circuit the pipeline:

      fetch_user(id)
      |> Result.and_then(&validate_permissions/1)
      |> Result.and_then(&perform_action/1)
      |> Result.map(&format_response/1)

  If any step fails, subsequent steps are skipped and the error propagates.
  """

  use ExUnit.Case, async: true

  alias FnTypes.Result

  # ============================================================================
  # USE CASE: Fetching Data from External Sources
  # ============================================================================

  describe "Use Case: Fetching user from database" do
    # When fetching data that may not exist, wrap the result in a Result type.
    # This makes the possibility of absence explicit in the type system.

    defp fetch_user(id) do
      users = %{1 => %{id: 1, name: "Alice"}, 2 => %{id: 2, name: "Bob"}}

      case Map.get(users, id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end

    test "returns {:ok, user} when user exists" do
      assert {:ok, %{id: 1, name: "Alice"}} = fetch_user(1)
    end

    test "returns {:error, :not_found} when user doesn't exist" do
      assert {:error, :not_found} = fetch_user(999)
    end

    test "checking if fetch succeeded with Result.ok?/1" do
      result = fetch_user(1)
      assert Result.ok?(result) == true

      result = fetch_user(999)
      assert Result.ok?(result) == false
    end

    test "safely accessing user data with Result.map/2" do
      # Transform the user data only if fetch succeeded
      result =
        fetch_user(1)
        |> Result.map(fn user -> String.upcase(user.name) end)

      assert result == {:ok, "ALICE"}

      # Error propagates unchanged
      result =
        fetch_user(999)
        |> Result.map(fn user -> String.upcase(user.name) end)

      assert result == {:error, :not_found}
    end
  end

  # ============================================================================
  # USE CASE: Chaining Multiple Fallible Operations
  # ============================================================================

  describe "Use Case: Multi-step user registration" do
    # When you have multiple operations that each can fail (validate email,
    # check username availability, create account), use and_then to chain them.
    # The chain stops at the first failure.

    defp validate_email(email) do
      if String.contains?(email, "@") do
        {:ok, email}
      else
        {:error, :invalid_email}
      end
    end

    defp check_username_available(username) do
      taken = ["admin", "root", "system"]

      if username in taken do
        {:error, :username_taken}
      else
        {:ok, username}
      end
    end

    defp create_account(email, username) do
      {:ok, %{id: 1, email: email, username: username}}
    end

    test "successful registration chains all steps" do
      result =
        {:ok, %{email: "user@example.com", username: "newuser"}}
        |> Result.and_then(fn data -> validate_email(data.email) |> Result.map(fn _ -> data end) end)
        |> Result.and_then(fn data ->
          check_username_available(data.username) |> Result.map(fn _ -> data end)
        end)
        |> Result.and_then(fn data -> create_account(data.email, data.username) end)

      assert {:ok, %{id: 1, email: "user@example.com", username: "newuser"}} = result
    end

    test "invalid email stops the chain early" do
      result =
        {:ok, %{email: "invalid-email", username: "newuser"}}
        |> Result.and_then(fn data -> validate_email(data.email) end)
        |> Result.and_then(fn _email -> raise "This should never be reached" end)

      assert result == {:error, :invalid_email}
    end

    test "taken username stops the chain" do
      result =
        {:ok, %{email: "user@example.com", username: "admin"}}
        |> Result.and_then(fn data -> validate_email(data.email) |> Result.map(fn _ -> data end) end)
        |> Result.and_then(fn data -> check_username_available(data.username) end)
        |> Result.and_then(fn _username -> raise "This should never be reached" end)

      assert result == {:error, :username_taken}
    end
  end

  # ============================================================================
  # USE CASE: Providing Fallback Values
  # ============================================================================

  describe "Use Case: Default values when operation fails" do
    # Sometimes you want a default value when an operation fails.
    # Use unwrap_or for static defaults, unwrap_or_else for computed defaults.

    defp get_user_preference(user_id, key) do
      preferences = %{
        1 => %{theme: "dark", language: "en"}
      }

      case get_in(preferences, [user_id, key]) do
        nil -> {:error, :preference_not_found}
        value -> {:ok, value}
      end
    end

    test "unwrap_or provides static fallback" do
      # User 1 has theme preference
      theme = get_user_preference(1, :theme) |> Result.unwrap_or("light")
      assert theme == "dark"

      # User 2 doesn't exist, use default
      theme = get_user_preference(2, :theme) |> Result.unwrap_or("light")
      assert theme == "light"
    end

    test "unwrap_or_else computes fallback based on error" do
      result =
        get_user_preference(999, :theme)
        |> Result.unwrap_or_else(fn reason ->
          case reason do
            :preference_not_found -> "system_default"
            :user_not_found -> "guest_theme"
            _ -> "fallback"
          end
        end)

      assert result == "system_default"
    end

    test "or_else allows recovery with a new Result" do
      result =
        get_user_preference(999, :theme)
        |> Result.or_else(fn _reason ->
          # Try system default instead
          {:ok, "system_default"}
        end)

      assert result == {:ok, "system_default"}
    end
  end

  # ============================================================================
  # USE CASE: Collecting Results from Multiple Operations
  # ============================================================================

  describe "Use Case: Batch operations that must all succeed" do
    # When processing a list of items where all must succeed (like a transaction),
    # use Result.collect/1 or Result.traverse/2.

    defp validate_item(item) do
      cond do
        item.quantity <= 0 -> {:error, {:invalid_quantity, item.id}}
        item.price < 0 -> {:error, {:invalid_price, item.id}}
        true -> {:ok, item}
      end
    end

    test "collect gathers all successful results" do
      results = [
        {:ok, %{id: 1, total: 100}},
        {:ok, %{id: 2, total: 200}},
        {:ok, %{id: 3, total: 300}}
      ]

      assert {:ok, items} = Result.collect(results)
      assert length(items) == 3
      assert Enum.sum(Enum.map(items, & &1.total)) == 600
    end

    test "collect returns first error when any operation fails" do
      results = [
        {:ok, %{id: 1, total: 100}},
        {:error, :item_2_failed},
        {:ok, %{id: 3, total: 300}},
        {:error, :item_4_failed}
      ]

      # Returns first error, stops processing
      assert {:error, :item_2_failed} = Result.collect(results)
    end

    test "traverse validates a list of items" do
      items = [
        %{id: 1, quantity: 5, price: 10.0},
        %{id: 2, quantity: 3, price: 20.0},
        %{id: 3, quantity: 2, price: 15.0}
      ]

      assert {:ok, validated} = Result.traverse(items, &validate_item/1)
      assert length(validated) == 3
    end

    test "traverse stops at first invalid item" do
      items = [
        %{id: 1, quantity: 5, price: 10.0},
        %{id: 2, quantity: -1, price: 20.0},
        %{id: 3, quantity: 2, price: 15.0}
      ]

      assert {:error, {:invalid_quantity, 2}} = Result.traverse(items, &validate_item/1)
    end
  end

  # ============================================================================
  # USE CASE: Partial Success Handling
  # ============================================================================

  describe "Use Case: Processing batch where some failures are acceptable" do
    # Sometimes you want to process a batch and collect both successes and failures
    # separately, rather than failing on the first error.

    defp send_notification(user) do
      if user.email_verified do
        {:ok, %{user_id: user.id, sent: true}}
      else
        {:error, {:unverified_email, user.id}}
      end
    end

    test "partition separates successes from failures" do
      users = [
        %{id: 1, email_verified: true},
        %{id: 2, email_verified: false},
        %{id: 3, email_verified: true},
        %{id: 4, email_verified: false}
      ]

      results = Enum.map(users, &send_notification/1)
      %{ok: successes, errors: failures} = Result.partition(results)

      assert length(successes) == 2
      assert length(failures) == 2
      assert Enum.all?(successes, fn r -> r.sent == true end)
      assert {:unverified_email, 2} in failures
    end

    test "cat_ok extracts only successful values" do
      results = [
        {:ok, "email_1@example.com"},
        {:error, :invalid},
        {:ok, "email_2@example.com"},
        {:error, :bounced}
      ]

      emails = Result.cat_ok(results)
      assert emails == ["email_1@example.com", "email_2@example.com"]
    end

    test "cat_errors extracts only error reasons" do
      results = [
        {:ok, "success"},
        {:error, :timeout},
        {:ok, "success"},
        {:error, :connection_refused}
      ]

      errors = Result.cat_errors(results)
      assert errors == [:timeout, :connection_refused]
    end
  end

  # ============================================================================
  # USE CASE: Error Transformation and Normalization
  # ============================================================================

  describe "Use Case: Normalizing errors from different sources" do
    # Different libraries return errors in different formats. Use map_error
    # to normalize them into a consistent format for your application.

    defp call_external_api do
      # Simulating different error formats from external sources
      {:error, %{status: 404, message: "Resource not found"}}
    end

    defp call_database do
      {:error, :connection_timeout}
    end

    defp normalize_error(%{status: 404}), do: :not_found
    defp normalize_error(%{status: 500}), do: :server_error
    defp normalize_error(:connection_timeout), do: :database_unavailable
    defp normalize_error(other), do: {:unknown, other}

    test "map_error transforms external API errors" do
      result =
        call_external_api()
        |> Result.map_error(&normalize_error/1)

      assert result == {:error, :not_found}
    end

    test "map_error transforms database errors" do
      result =
        call_database()
        |> Result.map_error(&normalize_error/1)

      assert result == {:error, :database_unavailable}
    end

    test "bimap transforms both success and error" do
      api_result = {:ok, %{data: [1, 2, 3], meta: %{}}}

      result =
        api_result
        |> Result.bimap(
          on_ok: fn response -> response.data end,
          on_error: &normalize_error/1
        )

      assert result == {:ok, [1, 2, 3]}
    end
  end

  # ============================================================================
  # USE CASE: Side Effects in Pipelines
  # ============================================================================

  describe "Use Case: Logging and telemetry in pipelines" do
    # Use tap/2 for logging successful operations and tap_error/2 for logging
    # failures without interrupting the pipeline.

    test "tap executes side effect for success without changing result" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        {:ok, %{user_id: 123, action: "purchase"}}
        |> Result.tap(fn event ->
          Agent.update(log, fn logs -> [{:success, event.action} | logs] end)
        end)
        |> Result.map(fn event -> Map.put(event, :processed, true) end)

      assert result == {:ok, %{user_id: 123, action: "purchase", processed: true}}
      assert Agent.get(log, & &1) == [{:success, "purchase"}]
      Agent.stop(log)
    end

    test "tap_error logs failures for monitoring" do
      error_log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        {:error, :payment_declined}
        |> Result.tap_error(fn reason ->
          Agent.update(error_log, fn logs -> [{:error, reason, DateTime.utc_now()} | logs] end)
        end)

      assert result == {:error, :payment_declined}
      [{:error, :payment_declined, _timestamp}] = Agent.get(error_log, & &1)
      Agent.stop(error_log)
    end
  end

  # ============================================================================
  # USE CASE: Combining Multiple Independent Results
  # ============================================================================

  describe "Use Case: Fetching data from multiple sources" do
    # When you need data from multiple independent sources and want to combine
    # them only if all succeed, use combine/2 or zip_with/3.

    defp fetch_user_profile(user_id) do
      {:ok, %{id: user_id, name: "Alice"}}
    end

    defp fetch_user_settings(user_id) do
      {:ok, %{user_id: user_id, theme: "dark", notifications: true}}
    end

    defp fetch_user_stats(_user_id) do
      {:error, :stats_unavailable}
    end

    test "combine merges two successful results into a tuple" do
      profile = fetch_user_profile(1)
      settings = fetch_user_settings(1)

      result = Result.combine(profile, settings)

      assert {:ok, {%{id: 1, name: "Alice"}, %{theme: "dark"}}} =
               Result.map(result, fn {p, s} -> {p, Map.take(s, [:theme])} end)
    end

    test "combine fails if any source fails" do
      profile = fetch_user_profile(1)
      stats = fetch_user_stats(1)

      result = Result.combine(profile, stats)

      assert result == {:error, :stats_unavailable}
    end

    test "zip_with combines results using a function" do
      profile = fetch_user_profile(1)
      settings = fetch_user_settings(1)

      result =
        Result.zip_with(profile, settings, fn p, s ->
          Map.merge(p, %{settings: s})
        end)

      assert {:ok, %{id: 1, name: "Alice", settings: %{theme: "dark"}}} =
               Result.map(result, fn r -> Map.update!(r, :settings, &Map.take(&1, [:theme])) end)
    end
  end

  # ============================================================================
  # USE CASE: Handling Exceptions Safely
  # ============================================================================

  describe "Use Case: Wrapping functions that might throw" do
    # When calling code that might raise exceptions (like parsing JSON or
    # doing arithmetic), use try_with to convert exceptions to Results.

    test "try_with catches exceptions and returns error" do
      result = Result.try_with(fn -> JSON.decode!("invalid json") end)

      assert {:error, %JSON.DecodeError{}} = result
    end

    test "try_with wraps successful computation" do
      result = Result.try_with(fn -> JSON.decode!(~s({"key": "value"})) end)

      assert result == {:ok, %{"key" => "value"}}
    end

    test "try_with can pass argument to function" do
      result = Result.try_with(fn x -> x * 2 end, 21)

      assert result == {:ok, 42}
    end

    test "safe division with try_with" do
      safe_divide = fn a, b ->
        Result.try_with(fn -> div(a, b) end)
      end

      assert safe_divide.(10, 2) == {:ok, 5}
      assert {:error, %ArithmeticError{}} = safe_divide.(10, 0)
    end
  end

  # ============================================================================
  # USE CASE: Converting from Nullable Values
  # ============================================================================

  describe "Use Case: Converting Map.get results to Result" do
    # Many Elixir functions return nil for missing values. Use from_nilable
    # to convert these to explicit Result types.

    test "from_nilable converts present value to ok" do
      config = %{api_key: "secret123", timeout: 5000}

      result = Result.from_nilable(config[:api_key], :missing_api_key)

      assert result == {:ok, "secret123"}
    end

    test "from_nilable converts nil to error" do
      config = %{timeout: 5000}

      result = Result.from_nilable(config[:api_key], :missing_api_key)

      assert result == {:error, :missing_api_key}
    end

    test "from_nilable_lazy computes error only when needed" do
      config = %{api_key: "secret123"}

      # Error function is not called since value exists
      result =
        Result.from_nilable_lazy(config[:api_key], fn ->
          raise "This should not be called"
        end)

      assert result == {:ok, "secret123"}
    end
  end

  # ============================================================================
  # USE CASE: Pipeline with Step Context
  # ============================================================================

  describe "Use Case: Tracking which step failed in a pipeline" do
    # In complex pipelines, knowing which step failed is valuable for debugging.
    # Use with_step/2 to wrap errors with step context.

    defp validate_input(data) do
      if Map.has_key?(data, :required_field) do
        {:ok, data}
      else
        {:error, :missing_required_field}
      end
    end

    defp process_data(data) do
      {:ok, Map.put(data, :processed, true)}
    end

    defp save_to_database(_data) do
      {:error, :connection_failed}
    end

    test "with_step wraps error with step name (recommended pattern)" do
      # Recommended: Wrap each step's result immediately inside and_then
      # This way only the failing step's name is in the error
      result =
        {:ok, %{name: "test", required_field: true}}
        |> Result.and_then(fn d -> validate_input(d) |> Result.with_step(:validate_input) end)
        |> Result.and_then(fn d -> process_data(d) |> Result.with_step(:process_data) end)
        |> Result.and_then(fn d -> save_to_database(d) |> Result.with_step(:save_to_database) end)

      assert {:error, {:step_failed, :save_to_database, :connection_failed}} = result
    end

    test "with_step identifies which step failed in validation" do
      # Validation fails - only validate_input step name appears
      result =
        {:ok, %{name: "test"}}
        |> Result.and_then(fn d -> validate_input(d) |> Result.with_step(:validate_input) end)
        |> Result.and_then(fn d -> process_data(d) |> Result.with_step(:process_data) end)

      assert {:error, {:step_failed, :validate_input, :missing_required_field}} = result
    end

    test "with_step accumulates when used outside and_then (shows anti-pattern)" do
      # Anti-pattern: Using with_step outside and_then causes cumulative wrapping
      # Each with_step wraps the error again as it passes through
      result =
        {:ok, %{name: "test"}}
        |> Result.and_then(&validate_input/1)
        |> Result.with_step(:validate_input)
        |> Result.and_then(&process_data/1)
        |> Result.with_step(:process_data)

      # Error gets wrapped by each subsequent with_step it passes through
      assert {:error, {:step_failed, :process_data, {:step_failed, :validate_input, :missing_required_field}}} =
               result
    end

    test "successful pipeline doesn't add step context" do
      result =
        {:ok, %{required_field: true}}
        |> Result.and_then(fn d -> validate_input(d) |> Result.with_step(:validate_input) end)
        |> Result.and_then(fn d -> process_data(d) |> Result.with_step(:process_data) end)

      assert {:ok, %{required_field: true, processed: true}} = result
    end
  end

  # ============================================================================
  # Core API Tests (Comprehensive Coverage)
  # ============================================================================

  describe "Result.ok/1 and Result.error/1" do
    test "ok wraps any value" do
      assert Result.ok(42) == {:ok, 42}
      assert Result.ok(nil) == {:ok, nil}
      assert Result.ok(%{complex: [1, 2, 3]}) == {:ok, %{complex: [1, 2, 3]}}
    end

    test "error wraps any reason" do
      assert Result.error(:not_found) == {:error, :not_found}
      assert Result.error("message") == {:error, "message"}
      assert Result.error(%{code: 404}) == {:error, %{code: 404}}
    end
  end

  describe "Result.ok?/1 and Result.error?/1" do
    test "ok? returns true for ok tuples" do
      assert Result.ok?({:ok, 42})
      assert Result.ok?({:ok, nil})
    end

    test "ok? returns false for error tuples and other values" do
      refute Result.ok?({:error, :reason})
      refute Result.ok?(:ok)
      refute Result.ok?(42)
    end

    test "error? returns true for error tuples" do
      assert Result.error?({:error, :reason})
      assert Result.error?({:error, nil})
    end

    test "error? returns false for ok tuples and other values" do
      refute Result.error?({:ok, 42})
      refute Result.error?(:error)
      refute Result.error?(nil)
    end
  end

  describe "Result.map/2" do
    test "transforms ok value" do
      assert Result.map({:ok, 5}, &(&1 * 2)) == {:ok, 10}
      assert Result.map({:ok, "hello"}, &String.upcase/1) == {:ok, "HELLO"}
    end

    test "passes through error unchanged" do
      assert Result.map({:error, :not_found}, &(&1 * 2)) == {:error, :not_found}
    end
  end

  describe "Result.and_then/2 (bind/flatMap)" do
    test "chains successful operations" do
      result =
        {:ok, 5}
        |> Result.and_then(&{:ok, &1 * 2})
        |> Result.and_then(&{:ok, &1 + 1})

      assert result == {:ok, 11}
    end

    test "short-circuits on error" do
      result =
        {:ok, 5}
        |> Result.and_then(fn _ -> {:error, :failed} end)
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      assert result == {:error, :failed}
    end
  end

  describe "Result.unwrap!/1" do
    test "returns value for ok" do
      assert Result.unwrap!({:ok, 42}) == 42
    end

    test "raises for error" do
      assert_raise ArgumentError, fn ->
        Result.unwrap!({:error, :reason})
      end
    end
  end

  describe "Result.flatten/1" do
    test "flattens nested results" do
      assert Result.flatten({:ok, {:ok, 42}}) == {:ok, 42}
      assert Result.flatten({:ok, {:error, :inner}}) == {:error, :inner}
      assert Result.flatten({:error, :outer}) == {:error, :outer}
    end
  end

  describe "Result.swap/1" do
    test "swaps ok and error" do
      assert Result.swap({:ok, 42}) == {:error, 42}
      assert Result.swap({:error, :reason}) == {:ok, :reason}
    end
  end

  describe "Result.to_bool/1" do
    test "converts to boolean" do
      assert Result.to_bool({:ok, 42}) == true
      assert Result.to_bool({:error, :reason}) == false
    end
  end

  describe "Result.to_option/1" do
    test "converts to nullable value" do
      assert Result.to_option({:ok, 42}) == 42
      assert Result.to_option({:error, :reason}) == nil
    end
  end

  describe "Result.reduce/3" do
    test "folds ok value" do
      assert Result.reduce({:ok, 5}, 10, &+/2) == 15
    end

    test "returns accumulator for error" do
      assert Result.reduce({:error, :reason}, 10, &+/2) == 10
    end
  end

  describe "Result.apply/2 (Applicative)" do
    test "applies wrapped function to wrapped value" do
      assert Result.apply({:ok, &String.upcase/1}, {:ok, "hello"}) == {:ok, "HELLO"}
      assert Result.apply({:error, :no_fn}, {:ok, "hello"}) == {:error, :no_fn}
      assert Result.apply({:ok, &String.upcase/1}, {:error, :no_val}) == {:error, :no_val}
    end
  end

  describe "Result.lift/1" do
    test "lifts function to work on Results" do
      upcase = Result.lift(&String.upcase/1)

      assert upcase.({:ok, "hello"}) == {:ok, "HELLO"}
      assert upcase.({:error, :reason}) == {:error, :reason}
    end
  end
end
