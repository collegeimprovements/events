defmodule FnTypes.ValidationTest do
  use ExUnit.Case, async: true

  alias FnTypes.Validation, as: V
  alias FnTypes.Error

  # ============================================
  # Core Construction
  # ============================================

  describe "ok/1" do
    test "wraps value in ok tuple" do
      assert V.ok(42) == {:ok, 42}
      assert V.ok("hello") == {:ok, "hello"}
      assert V.ok(%{a: 1}) == {:ok, %{a: 1}}
      assert V.ok(nil) == {:ok, nil}
    end
  end

  describe "error/1" do
    test "wraps single error in list" do
      assert V.error(:required) == {:error, [:required]}
      assert V.error("invalid") == {:error, ["invalid"]}
    end

    test "keeps list of errors as-is" do
      assert V.error([:a, :b]) == {:error, [:a, :b]}
    end
  end

  describe "new/1" do
    test "creates validation context from map" do
      assert {:context, %{name: "Alice"}, %{}} = V.new(%{name: "Alice"})
    end

    test "creates context from struct" do
      assert {:context, %URI{host: "example.com"}, %{}} = V.new(%URI{host: "example.com"})
    end
  end

  # ============================================
  # Type Checking
  # ============================================

  describe "valid?/1" do
    test "returns true for ok" do
      assert V.valid?({:ok, 42})
    end

    test "returns false for error" do
      refute V.valid?({:error, [:required]})
    end

    test "returns true for context with no errors" do
      assert V.valid?({:context, %{}, %{}})
    end

    test "returns false for context with errors" do
      refute V.valid?({:context, %{}, %{email: [:required]}})
    end
  end

  describe "invalid?/1" do
    test "returns true for error" do
      assert V.invalid?({:error, [:required]})
    end

    test "returns false for ok" do
      refute V.invalid?({:ok, 42})
    end
  end

  # ============================================
  # Single Value Validation
  # ============================================

  describe "validate/2" do
    test "returns ok when all validators pass" do
      result = V.validate("test@example.com", [V.required(), V.format(:email)])
      assert {:ok, "test@example.com"} = result
    end

    test "accumulates all errors" do
      result = V.validate("", [V.required(), V.min_length(5)])
      assert {:error, [:required, {:min_length, 5}]} = result
    end

    test "works with empty validator list" do
      assert {:ok, "anything"} = V.validate("anything", [])
    end
  end

  describe "check_value/3" do
    test "returns ok when predicate passes" do
      assert {:ok, 18} = V.check_value(18, &(&1 >= 18), :must_be_adult)
    end

    test "returns error when predicate fails" do
      assert {:error, [:must_be_adult]} = V.check_value(15, &(&1 >= 18), :must_be_adult)
    end

    test "accepts keyword options" do
      assert {:error, ["must be 18+"]} = V.check_value(15, &(&1 >= 18), message: "must be 18+")
    end
  end

  # ============================================
  # Field Validation
  # ============================================

  describe "field/4" do
    test "validates field and adds errors" do
      result =
        V.new(%{email: ""})
        |> V.field(:email, [V.required()])
        |> V.to_result()

      assert {:error, %{email: [:required]}} = result
    end

    test "passes when field is valid" do
      result =
        V.new(%{email: "test@example.com"})
        |> V.field(:email, [V.required(), V.format(:email)])
        |> V.to_result()

      assert {:ok, %{email: "test@example.com"}} = result
    end

    test "accumulates errors across multiple fields" do
      result =
        V.new(%{email: "", age: 15})
        |> V.field(:email, [V.required()])
        |> V.field(:age, [V.min(18)])
        |> V.to_result()

      assert {:error, errors} = result
      assert [:required] = errors.email
      assert [{:min, 18}] = errors.age
    end

    test "respects :when condition" do
      # Should validate when condition is true
      result =
        V.new(%{contact_method: :phone, phone: ""})
        |> V.field(:phone, [V.required()], when: &(&1[:contact_method] == :phone))
        |> V.to_result()

      assert {:error, %{phone: [:required]}} = result

      # Should skip validation when condition is false
      result =
        V.new(%{contact_method: :email, phone: ""})
        |> V.field(:phone, [V.required()], when: &(&1[:contact_method] == :phone))
        |> V.to_result()

      assert {:ok, _} = result
    end

    test "respects :unless condition" do
      result =
        V.new(%{is_guest: true, email: ""})
        |> V.field(:email, [V.required()], unless: & &1[:is_guest])
        |> V.to_result()

      assert {:ok, _} = result
    end

    test "applies :transform before validation" do
      result =
        V.new(%{email: "  TEST@EXAMPLE.COM  "})
        |> V.field(:email, [V.format(:email)],
          transform: fn s -> s |> String.trim() |> String.downcase() end
        )
        |> V.to_result()

      assert {:ok, _} = result
    end

    test "uses :default for nil values" do
      result =
        V.new(%{})
        |> V.field(:role, [V.inclusion([:admin, :user])], default: :user)
        |> V.to_result()

      assert {:ok, _} = result
    end
  end

  describe "check/4" do
    test "adds custom validation check" do
      result =
        V.new(%{password: "secret", password_confirmation: "different"})
        |> V.check(:password_confirmation, fn ctx ->
          if ctx.data.password == ctx.data.password_confirmation do
            :ok
          else
            {:error, :passwords_must_match}
          end
        end)
        |> V.to_result()

      assert {:error, %{password_confirmation: [:passwords_must_match]}} = result
    end

    test "passes when check succeeds" do
      result =
        V.new(%{password: "secret", password_confirmation: "secret"})
        |> V.check(:password_confirmation, fn ctx ->
          if ctx.data.password == ctx.data.password_confirmation, do: :ok, else: {:error, :mismatch}
        end)
        |> V.to_result()

      assert {:ok, _} = result
    end

    test "supports targeting different field" do
      result =
        V.new(%{start_date: ~D[2024-01-15], end_date: ~D[2024-01-10]})
        |> V.check(:end_date, fn ctx ->
          if ctx.data.end_date > ctx.data.start_date do
            :ok
          else
            {:error, :end_date, :must_be_after_start_date}
          end
        end)
        |> V.to_result()

      assert {:error, %{end_date: [:must_be_after_start_date]}} = result
    end
  end

  describe "global_check/2" do
    test "adds global validation affecting any field" do
      result =
        V.new(%{})
        |> V.global_check(fn ctx ->
          if Map.has_key?(ctx.data, :email) or Map.has_key?(ctx.data, :phone) do
            :ok
          else
            {:error, :email, :email_or_phone_required}
          end
        end)
        |> V.to_result()

      assert {:error, %{email: [:email_or_phone_required]}} = result
    end

    test "adds to :base when no field specified" do
      result =
        V.new(%{})
        |> V.global_check(fn _ -> {:error, :custom_error} end)
        |> V.to_result()

      assert {:error, %{base: [:custom_error]}} = result
    end
  end

  describe "fields/4" do
    test "validates multiple fields with same validators" do
      result =
        V.new(%{first_name: "", last_name: ""})
        |> V.fields([:first_name, :last_name], [V.required()])
        |> V.to_result()

      assert {:error, errors} = result
      assert errors.first_name == [:required]
      assert errors.last_name == [:required]
    end
  end

  describe "nested/4" do
    test "validates nested data" do
      result =
        V.new(%{user: %{email: "", name: "Alice"}})
        |> V.nested(:user, fn ctx ->
          ctx
          |> V.field(:email, [V.required()])
          |> V.field(:name, [V.required()])
        end)
        |> V.to_result()

      assert {:error, %{"user.email": [:required]}} = result
    end

    test "passes when nested data is valid" do
      result =
        V.new(%{user: %{email: "test@example.com", name: "Alice"}})
        |> V.nested(:user, fn ctx ->
          ctx
          |> V.field(:email, [V.required()])
          |> V.field(:name, [V.required()])
        end)
        |> V.to_result()

      assert {:ok, _} = result
    end

    test "errors when nested value is not a map" do
      result =
        V.new(%{user: "not a map"})
        |> V.nested(:user, fn ctx -> V.field(ctx, :email, [V.required()]) end)
        |> V.to_result()

      assert {:error, %{user: [:must_be_map]}} = result
    end
  end

  describe "each/4" do
    test "validates each item in a list" do
      result =
        V.new(%{items: [%{name: "A"}, %{name: ""}, %{name: "C"}]})
        |> V.each(:items, fn ctx ->
          V.field(ctx, :name, [V.required()])
        end)
        |> V.to_result()

      assert {:error, errors} = result
      assert errors[:"items.1.name"] == [:required]
      refute Map.has_key?(errors, :"items.0.name")
      refute Map.has_key?(errors, :"items.2.name")
    end

    test "errors when field is not a list" do
      result =
        V.new(%{items: "not a list"})
        |> V.each(:items, fn ctx -> ctx end)
        |> V.to_result()

      assert {:error, %{items: [:must_be_list]}} = result
    end
  end

  # ============================================
  # Applicative Operations
  # ============================================

  describe "map/2" do
    test "transforms ok value" do
      assert {:ok, 10} = V.map({:ok, 5}, &(&1 * 2))
    end

    test "passes through error" do
      assert {:error, [:a]} = V.map({:error, [:a]}, &(&1 * 2))
    end
  end

  describe "map2/3" do
    test "combines two ok values" do
      assert {:ok, 5} = V.map2({:ok, 2}, {:ok, 3}, &+/2)
    end

    test "accumulates errors from both" do
      assert {:error, [:a, :b]} = V.map2({:error, [:a]}, {:error, [:b]}, &+/2)
    end

    test "returns single error if only one fails" do
      assert {:error, [:b]} = V.map2({:ok, 1}, {:error, [:b]}, &+/2)
      assert {:error, [:a]} = V.map2({:error, [:a]}, {:ok, 2}, &+/2)
    end
  end

  describe "map3/4" do
    test "combines three ok values" do
      result =
        V.map3(
          {:ok, "email@example.com"},
          {:ok, "Alice"},
          {:ok, 25},
          fn e, n, a -> %{email: e, name: n, age: a} end
        )

      assert {:ok, %{email: "email@example.com", name: "Alice", age: 25}} = result
    end

    test "accumulates all errors" do
      result = V.map3({:error, [:a]}, {:error, [:b]}, {:error, [:c]}, fn _, _, _ -> :ok end)
      assert {:error, [:a, :b, :c]} = result
    end
  end

  describe "map_n/2" do
    test "combines N validations" do
      result =
        V.map_n(
          [{:ok, 1}, {:ok, 2}, {:ok, 3}, {:ok, 4}],
          fn [a, b, c, d] -> a + b + c + d end
        )

      assert {:ok, 10} = result
    end

    test "accumulates all errors" do
      result = V.map_n([{:ok, 1}, {:error, [:a]}, {:ok, 3}, {:error, [:b]}], fn _ -> :ok end)
      assert {:error, [:a, :b]} = result
    end
  end

  # ============================================
  # Collection Operations
  # ============================================

  describe "all/1" do
    test "returns ok with all values when all pass" do
      assert {:ok, [1, 2, 3]} = V.all([{:ok, 1}, {:ok, 2}, {:ok, 3}])
    end

    test "accumulates all errors" do
      assert {:error, [:a, :b]} = V.all([{:ok, 1}, {:error, [:a]}, {:error, [:b]}])
    end

    test "returns ok empty list for empty input" do
      assert {:ok, []} = V.all([])
    end
  end

  describe "traverse/2" do
    test "applies function and collects results" do
      result = V.traverse([1, 2, 3], fn x -> {:ok, x * 2} end)
      assert {:ok, [2, 4, 6]} = result
    end

    test "accumulates all errors" do
      result =
        V.traverse([1, -2, -3], fn x ->
          if x > 0, do: {:ok, x}, else: {:error, [{:negative, x}]}
        end)

      assert {:error, [{:negative, -2}, {:negative, -3}]} = result
    end
  end

  describe "traverse_indexed/2" do
    test "includes index in callback" do
      result =
        V.traverse_indexed(["a", "b", "c"], fn item, idx ->
          {:ok, {item, idx}}
        end)

      assert {:ok, [{"a", 0}, {"b", 1}, {"c", 2}]} = result
    end
  end

  describe "partition/1" do
    test "separates successes and failures" do
      result = V.partition([{:ok, 1}, {:error, [:a]}, {:ok, 3}, {:error, [:b]}])

      assert %{ok: [1, 3], errors: [[:a], [:b]]} = result
    end
  end

  # ============================================
  # Built-in Validators
  # ============================================

  describe "required/1" do
    test "fails for nil" do
      assert {:error, [:required]} = V.required().(nil)
    end

    test "fails for empty string" do
      assert {:error, [:required]} = V.required().("")
    end

    test "passes for any other value" do
      assert {:ok, "hello"} = V.required().("hello")
      assert {:ok, 0} = V.required().(0)
      assert {:ok, false} = V.required().(false)
    end

    test "accepts custom message" do
      assert {:error, ["is mandatory"]} = V.required(message: "is mandatory").(nil)
    end
  end

  describe "optional/1" do
    test "passes for nil without running validators" do
      assert {:ok, nil} = V.optional([V.format(:email)]).(nil)
    end

    test "runs validators for non-nil values" do
      assert {:ok, "test@example.com"} = V.optional([V.format(:email)]).("test@example.com")
      assert {:error, [{:format, :email}]} = V.optional([V.format(:email)]).("invalid")
    end
  end

  describe "format/2" do
    test "validates email format" do
      assert {:ok, "test@example.com"} = V.format(:email).("test@example.com")
      assert {:error, [{:format, :email}]} = V.format(:email).("invalid")
    end

    test "validates url format" do
      assert {:ok, "https://example.com"} = V.format(:url).("https://example.com")
      assert {:error, [{:format, :url}]} = V.format(:url).("not-a-url")
    end

    test "validates uuid format" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, ^uuid} = V.format(:uuid).(uuid)
      assert {:error, [{:format, :uuid}]} = V.format(:uuid).("not-a-uuid")
    end

    test "validates slug format" do
      assert {:ok, "my-slug-123"} = V.format(:slug).("my-slug-123")
      assert {:error, [{:format, :slug}]} = V.format(:slug).("Invalid Slug!")
    end

    test "validates custom regex" do
      regex = ~r/^[A-Z]{3}$/
      assert {:ok, "ABC"} = V.format(regex).("ABC")
      assert {:error, [{:format, :custom}]} = V.format(regex).("abc")
    end

    test "passes nil through" do
      assert {:ok, nil} = V.format(:email).(nil)
    end
  end

  describe "min/2 and max/2" do
    test "min validates minimum value" do
      assert {:ok, 20} = V.min(18).(20)
      assert {:error, [{:min, 18}]} = V.min(18).(15)
    end

    test "max validates maximum value" do
      assert {:ok, 50} = V.max(100).(50)
      assert {:error, [{:max, 100}]} = V.max(100).(150)
    end

    test "passes nil through" do
      assert {:ok, nil} = V.min(0).(nil)
      assert {:ok, nil} = V.max(100).(nil)
    end
  end

  describe "between/3" do
    test "validates range" do
      assert {:ok, 5} = V.between(1, 10).(5)
      assert {:error, [{:between, 1, 10}]} = V.between(1, 10).(15)
      assert {:error, [{:between, 1, 10}]} = V.between(1, 10).(0)
    end
  end

  describe "positive/1 and non_negative/1" do
    test "positive requires > 0" do
      assert {:ok, 1} = V.positive().(1)
      assert {:error, [:must_be_positive]} = V.positive().(0)
      assert {:error, [:must_be_positive]} = V.positive().(-1)
    end

    test "non_negative requires >= 0" do
      assert {:ok, 0} = V.non_negative().(0)
      assert {:ok, 1} = V.non_negative().(1)
      assert {:error, [:must_be_non_negative]} = V.non_negative().(-1)
    end
  end

  describe "min_length/2 and max_length/2" do
    test "validates string length" do
      assert {:ok, "hello"} = V.min_length(3).("hello")
      assert {:error, [{:min_length, 5}]} = V.min_length(5).("hi")

      assert {:ok, "hi"} = V.max_length(5).("hi")
      assert {:error, [{:max_length, 3}]} = V.max_length(3).("hello")
    end

    test "validates list length" do
      assert {:ok, [1, 2, 3]} = V.min_length(2).([1, 2, 3])
      assert {:error, [{:min_length, 5}]} = V.min_length(5).([1, 2])

      assert {:ok, [1, 2]} = V.max_length(5).([1, 2])
      assert {:error, [{:max_length, 2}]} = V.max_length(2).([1, 2, 3])
    end
  end

  describe "exact_length/2" do
    test "validates exact length" do
      assert {:ok, "hello"} = V.exact_length(5).("hello")
      assert {:error, [{:length, 5}]} = V.exact_length(5).("hi")
    end
  end

  describe "inclusion/2 and exclusion/2" do
    test "inclusion validates value is in list" do
      assert {:ok, :active} = V.inclusion([:active, :inactive]).(:active)

      assert {:error, [{:inclusion, [:active, :inactive]}]} =
               V.inclusion([:active, :inactive]).(:deleted)
    end

    test "exclusion validates value is not in list" do
      assert {:ok, :user} = V.exclusion([:admin, :superuser]).(:user)
      assert {:error, [{:exclusion, [:admin]}]} = V.exclusion([:admin]).(:admin)
    end
  end

  describe "type/2" do
    test "validates type" do
      assert {:ok, "hello"} = V.type(:string).("hello")
      assert {:error, [{:type, :string}]} = V.type(:string).(123)

      assert {:ok, 42} = V.type(:integer).(42)
      assert {:error, [{:type, :integer}]} = V.type(:integer).("42")

      assert {:ok, true} = V.type(:boolean).(true)
      assert {:ok, %{}} = V.type(:map).(%{})
      assert {:ok, []} = V.type(:list).([])
    end
  end

  describe "predicate/2" do
    test "validates with custom predicate" do
      assert {:ok, 5} = V.predicate(&(&1 > 0), :must_be_positive).(5)
      assert {:error, [:must_be_positive]} = V.predicate(&(&1 > 0), :must_be_positive).(-1)
    end

    test "accepts keyword options" do
      validator = V.predicate(&String.contains?(&1, "@"), message: "must contain @")
      assert {:error, ["must contain @"]} = validator.("test")
    end
  end

  describe "equals/2 and not_equals/2" do
    test "equals validates equality" do
      assert {:ok, "expected"} = V.equals("expected").("expected")
      assert {:error, [:not_equal]} = V.equals("expected").("other")
    end

    test "not_equals validates inequality" do
      assert {:ok, "allowed"} = V.not_equals("forbidden").("allowed")
      assert {:error, [:equals_forbidden_value]} = V.not_equals("forbidden").("forbidden")
    end
  end

  describe "past/1 and future/1" do
    test "past validates date is in past" do
      past_date = Date.add(Date.utc_today(), -30)
      future_date = Date.add(Date.utc_today(), 30)

      assert {:ok, ^past_date} = V.past().(past_date)
      assert {:error, [:must_be_in_past]} = V.past().(future_date)
    end

    test "future validates date is in future" do
      past_date = Date.add(Date.utc_today(), -30)
      future_date = Date.add(Date.utc_today(), 30)

      assert {:ok, ^future_date} = V.future().(future_date)
      assert {:error, [:must_be_in_future]} = V.future().(past_date)
    end
  end

  describe "acceptance/1" do
    test "requires true" do
      assert {:ok, true} = V.acceptance().(true)
      assert {:error, [:must_be_accepted]} = V.acceptance().(false)
      assert {:error, [:must_be_accepted]} = V.acceptance().(nil)
    end
  end

  # ============================================
  # Cross-Field Validators
  # ============================================

  describe "matches_field/3" do
    test "validates two fields match" do
      ctx = %{
        data: %{password: "secret", confirm: "secret"},
        field: :confirm,
        value: "secret",
        errors: %{}
      }

      assert :ok = V.matches_field(ctx, :password)

      ctx = %{
        data: %{password: "secret", confirm: "different"},
        field: :confirm,
        value: "different",
        errors: %{}
      }

      assert {:error, {:must_match, :password}} = V.matches_field(ctx, :password)
    end
  end

  describe "greater_than_field/3" do
    test "validates field is greater than another" do
      ctx = %{data: %{start: 1, end: 10}, field: :end, value: 10, errors: %{}}
      assert :ok = V.greater_than_field(ctx, :start)

      ctx = %{data: %{start: 10, end: 5}, field: :end, value: 5, errors: %{}}
      assert {:error, {:must_be_greater_than, :start}} = V.greater_than_field(ctx, :start)
    end
  end

  describe "at_least_one_of/3" do
    test "requires at least one field present" do
      ctx = %{data: %{email: "test@example.com"}, field: nil, value: nil, errors: %{}}
      assert :ok = V.at_least_one_of(ctx, [:email, :phone])

      ctx = %{data: %{}, field: nil, value: nil, errors: %{}}

      assert {:error, :email, {:at_least_one_required, [:email, :phone]}} =
               V.at_least_one_of(ctx, [:email, :phone])
    end
  end

  describe "exactly_one_of/3" do
    test "requires exactly one field present" do
      ctx = %{data: %{email: "test@example.com"}, field: nil, value: nil, errors: %{}}
      assert :ok = V.exactly_one_of(ctx, [:email, :phone])

      ctx = %{data: %{email: "test@example.com", phone: "123"}, field: nil, value: nil, errors: %{}}

      assert {:error, :email, {:exactly_one_required, [:email, :phone]}} =
               V.exactly_one_of(ctx, [:email, :phone])
    end
  end

  # ============================================
  # Conversion
  # ============================================

  describe "to_result/1" do
    test "converts context to result" do
      assert {:ok, %{email: "test@example.com"}} =
               V.new(%{email: "test@example.com"})
               |> V.field(:email, [V.required()])
               |> V.to_result()

      assert {:error, %{email: [:required]}} =
               V.new(%{email: ""})
               |> V.field(:email, [V.required()])
               |> V.to_result()
    end

    test "passes through ok/error tuples" do
      assert {:ok, 42} = V.to_result({:ok, 42})
      assert {:error, [:a]} = V.to_result({:error, [:a]})
    end
  end

  describe "to_error/2" do
    test "converts to FnTypes.Error on failure" do
      result =
        V.new(%{email: ""})
        |> V.field(:email, [V.required()])
        |> V.to_error()

      assert {:error,
              %Error{
                type: :validation,
                details: %{
                  error_count: 1,
                  errors: %{email: [:required]},
                  fields: [:email]
                }
              }} = result
    end

    test "returns ok unchanged" do
      result =
        V.new(%{email: "test@example.com"})
        |> V.field(:email, [V.required()])
        |> V.to_error()

      assert {:ok, %{email: "test@example.com"}} = result
    end
  end

  describe "from_result/1" do
    test "converts from result" do
      assert {:ok, 42} = V.from_result({:ok, 42})
      assert {:error, [:not_found]} = V.from_result({:error, :not_found})
      assert {:error, [:a, :b]} = V.from_result({:error, [:a, :b]})
    end
  end

  describe "from_maybe/2" do
    test "converts from maybe" do
      assert {:ok, 42} = V.from_maybe({:some, 42}, :required)
      assert {:error, [:required]} = V.from_maybe(:none, :required)
    end
  end

  describe "to_maybe/1" do
    test "converts to maybe" do
      assert {:some, 42} = V.to_maybe({:ok, 42})
      assert :none = V.to_maybe({:error, [:a]})
    end
  end

  # ============================================
  # Utilities
  # ============================================

  describe "errors/1" do
    test "extracts errors from validation" do
      assert [:a, :b] = V.errors({:error, [:a, :b]})
      assert [] = V.errors({:ok, 42})
      assert %{email: [:required]} = V.errors({:context, %{}, %{email: [:required]}})
    end
  end

  describe "value/1" do
    test "extracts value from validation" do
      assert 42 = V.value({:ok, 42})
      assert nil == V.value({:error, [:a]})
      assert %{name: "Alice"} = V.value({:context, %{name: "Alice"}, %{}})
    end
  end

  describe "unwrap!/1" do
    test "returns value on ok" do
      assert 42 = V.unwrap!({:ok, 42})
    end

    test "raises on error" do
      assert_raise ArgumentError, ~r/Validation failed/, fn ->
        V.unwrap!({:error, [:required]})
      end
    end
  end

  describe "unwrap_or/2" do
    test "returns value on ok" do
      assert 42 = V.unwrap_or({:ok, 42}, 0)
    end

    test "returns default on error" do
      assert 0 = V.unwrap_or({:error, [:a]}, 0)
    end
  end

  describe "tap/2 and tap_error/2" do
    test "tap executes function on ok" do
      {:ok, value} = {:ok, 42} |> V.tap(&send(self(), {:tapped, &1}))
      assert value == 42
      assert_receive {:tapped, 42}
    end

    test "tap_error executes function on error" do
      {:error, errors} = {:error, [:a]} |> V.tap_error(&send(self(), {:tapped, &1}))
      assert errors == [:a]
      assert_receive {:tapped, [:a]}
    end
  end

  describe "map_error/2" do
    test "transforms errors" do
      assert {:error, ["a", "b"]} = V.map_error({:error, [:a, :b]}, &Atom.to_string/1)
    end
  end

  describe "flatten/1" do
    test "flattens nested validation" do
      assert {:ok, 42} = V.flatten({:ok, {:ok, 42}})
      assert {:error, [:a]} = V.flatten({:ok, {:error, [:a]}})
      assert {:error, [:a]} = V.flatten({:error, [:a]})
    end
  end

  # ============================================
  # Composition
  # ============================================

  describe "compose/1" do
    test "composes multiple validators into one" do
      email_validator = V.compose([V.required(), V.format(:email), V.max_length(255)])

      assert {:ok, "test@example.com"} = email_validator.("test@example.com")
      assert {:error, _} = email_validator.("")
    end
  end

  describe "named/2" do
    test "creates named validator" do
      email = V.named(:email, [V.required(), V.format(:email)])
      assert {:ok, "test@example.com"} = email.("test@example.com")
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "complex validation scenarios" do
    test "user registration form validation" do
      params = %{
        email: "invalid-email",
        username: "ab",
        password: "short",
        password_confirmation: "different",
        age: 15,
        terms_accepted: false
      }

      result =
        V.new(params)
        |> V.field(:email, [V.required(), V.format(:email)])
        |> V.field(:username, [V.required(), V.min_length(3), V.max_length(20)])
        |> V.field(:password, [V.required(), V.min_length(8)])
        |> V.field(:password_confirmation, [V.required()])
        |> V.check(:password_confirmation, &V.matches_field(&1, :password))
        |> V.field(:age, [V.required(), V.min(18, message: "must be 18 or older")])
        |> V.field(:terms_accepted, [V.acceptance(message: "must accept terms")])
        |> V.to_result()

      assert {:error, errors} = result
      assert Enum.member?(errors.email, {:format, :email})
      assert Enum.member?(errors.username, {:min_length, 3})
      assert Enum.member?(errors.password, {:min_length, 8})
      assert Enum.member?(errors.password_confirmation, {:must_match, :password})
      assert Enum.member?(errors.age, "must be 18 or older")
      assert Enum.member?(errors.terms_accepted, "must accept terms")
    end

    test "conditional validation based on other fields" do
      # When billing address is same as shipping, only validate shipping
      params = %{
        same_billing_address: true,
        shipping_address: %{street: "", city: "NYC"},
        billing_address: nil
      }

      result =
        V.new(params)
        |> V.nested(:shipping_address, fn ctx ->
          ctx
          |> V.field(:street, [V.required()])
          |> V.field(:city, [V.required()])
        end)
        |> V.nested(
          :billing_address,
          fn ctx ->
            ctx
            |> V.field(:street, [V.required()])
            |> V.field(:city, [V.required()])
          end,
          unless: & &1[:same_billing_address]
        )
        |> V.to_result()

      assert {:error, errors} = result
      # Only shipping address errors, not billing
      assert Map.has_key?(errors, :"shipping_address.street")
      refute Map.has_key?(errors, :"billing_address.street")
    end

    test "building map with map3" do
      params = %{email: "test@example.com", name: "Alice", age: 25}

      result =
        V.map3(
          V.validate(params[:email], [V.required(), V.format(:email)]),
          V.validate(params[:name], [V.required(), V.min_length(2)]),
          V.validate(params[:age], [V.required(), V.min(18)]),
          fn email, name, age ->
            %{email: email, name: name, age: age}
          end
        )

      assert {:ok, %{email: "test@example.com", name: "Alice", age: 25}} = result
    end

    test "validating list of items with traverse" do
      items = [
        %{name: "Item 1", price: 10.0},
        %{name: "", price: -5.0},
        %{name: "Item 3", price: 0}
      ]

      result =
        V.traverse_indexed(items, fn item, index ->
          V.new(item)
          |> V.field(:name, [V.required()])
          |> V.field(:price, [V.positive()])
          |> V.to_result()
          |> case do
            {:ok, _} = ok -> ok
            {:error, errors} -> {:error, [{:item, index, errors}]}
          end
        end)

      assert {:error, errors} = result

      assert Enum.any?(errors, fn
               {:item, 1, _} -> true
               _ -> false
             end)

      assert Enum.any?(errors, fn
               {:item, 2, _} -> true
               _ -> false
             end)
    end
  end
end
