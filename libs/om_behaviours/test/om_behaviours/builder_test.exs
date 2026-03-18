defmodule OmBehaviours.BuilderTest do
  use ExUnit.Case, async: true

  alias OmBehaviours.Builder

  # --- Test support modules ---

  defmodule SimpleBuilder do
    use OmBehaviours.Builder

    defstruct [:data, operations: []]

    @impl true
    def new(data, _opts \\ []) do
      %__MODULE__{data: data, operations: []}
    end

    @impl true
    def compose(builder, operation) do
      %{builder | operations: builder.operations ++ [operation]}
    end

    @impl true
    def build(%__MODULE__{data: data, operations: ops}) do
      Enum.reduce(ops, data, fn
        {:multiply, n}, acc -> acc * n
        {:add, n}, acc -> acc + n
        {:negate}, acc -> -acc
      end)
    end

    defcompose multiply(builder, n) do
      compose(builder, {:multiply, n})
    end

    defcompose add(builder, n) do
      compose(builder, {:add, n})
    end

    defcompose negate(builder) do
      compose(builder, {:negate})
    end
  end

  defmodule ValidationBuilder do
    use OmBehaviours.Builder

    defstruct [:data, rules: [], errors: []]

    @impl true
    def new(data, _opts \\ []) do
      %__MODULE__{data: data, rules: [], errors: []}
    end

    @impl true
    def compose(builder, rule) do
      %{builder | rules: builder.rules ++ [rule]}
    end

    @impl true
    def build(%__MODULE__{data: data, rules: rules}) do
      errors =
        Enum.reduce(rules, [], fn rule, acc ->
          case validate(rule, data) do
            :ok -> acc
            {:error, field, msg} -> [{field, msg} | acc]
          end
        end)

      case errors do
        [] -> {:ok, data}
        errors -> {:error, Enum.reverse(errors)}
      end
    end

    defp validate({:required, field}, data) do
      case Map.get(data, field) do
        nil -> {:error, field, "is required"}
        "" -> {:error, field, "is required"}
        _ -> :ok
      end
    end

    defp validate({:min_length, field, min}, data) do
      value = Map.get(data, field, "")

      if String.length(to_string(value)) >= min,
        do: :ok,
        else: {:error, field, "must be at least #{min} characters"}
    end

    defcompose required(builder, field) do
      compose(builder, {:required, field})
    end

    defcompose min_length(builder, field, min) do
      compose(builder, {:min_length, field, min})
    end
  end

  defmodule PlainModule do
    def hello, do: :world
  end

  # --- implements?/1 tests ---

  describe "implements?/1" do
    test "returns true for modules using Builder" do
      assert Builder.implements?(SimpleBuilder)
      assert Builder.implements?(ValidationBuilder)
    end

    test "returns false for plain modules" do
      refute Builder.implements?(PlainModule)
    end

    test "returns false for non-existent modules" do
      refute Builder.implements?(NonExistent.Builder)
    end
  end

  # --- new/2 tests ---

  describe "new/2" do
    test "creates a builder struct with initial data" do
      builder = SimpleBuilder.new(10)

      assert %SimpleBuilder{} = builder
      assert builder.data == 10
      assert builder.operations == []
    end

    test "creates a validation builder with initial data" do
      builder = ValidationBuilder.new(%{name: "test"})

      assert %ValidationBuilder{} = builder
      assert builder.data == %{name: "test"}
      assert builder.rules == []
    end
  end

  # --- compose/2 tests ---

  describe "compose/2" do
    test "adds operations to the builder" do
      builder =
        SimpleBuilder.new(5)
        |> SimpleBuilder.compose({:add, 3})

      assert builder.operations == [{:add, 3}]
    end

    test "preserves previous operations" do
      builder =
        SimpleBuilder.new(5)
        |> SimpleBuilder.compose({:add, 3})
        |> SimpleBuilder.compose({:multiply, 2})

      assert builder.operations == [{:add, 3}, {:multiply, 2}]
    end

    test "returns a builder struct (chainable)" do
      result =
        SimpleBuilder.new(5)
        |> SimpleBuilder.compose({:add, 1})

      assert %SimpleBuilder{} = result
    end
  end

  # --- build/1 tests ---

  describe "build/1" do
    test "applies operations in order" do
      # (5 + 3) * 2 = 16
      result =
        SimpleBuilder.new(5)
        |> SimpleBuilder.compose({:add, 3})
        |> SimpleBuilder.compose({:multiply, 2})
        |> SimpleBuilder.build()

      assert result == 16
    end

    test "returns raw data when no operations" do
      result =
        SimpleBuilder.new(42)
        |> SimpleBuilder.build()

      assert result == 42
    end

    test "handles single operation" do
      result =
        SimpleBuilder.new(7)
        |> SimpleBuilder.compose({:multiply, 3})
        |> SimpleBuilder.build()

      assert result == 21
    end
  end

  # --- defcompose tests ---

  describe "defcompose macro" do
    test "generates chainable functions" do
      result =
        SimpleBuilder.new(10)
        |> SimpleBuilder.add(5)
        |> SimpleBuilder.multiply(3)
        |> SimpleBuilder.build()

      # (10 + 5) * 3 = 45
      assert result == 45
    end

    test "zero-arity operations work" do
      result =
        SimpleBuilder.new(5)
        |> SimpleBuilder.negate()
        |> SimpleBuilder.build()

      assert result == -5
    end

    test "chains multiple defcompose functions" do
      result =
        SimpleBuilder.new(2)
        |> SimpleBuilder.multiply(3)
        |> SimpleBuilder.add(4)
        |> SimpleBuilder.multiply(2)
        |> SimpleBuilder.build()

      # ((2 * 3) + 4) * 2 = 20
      assert result == 20
    end
  end

  # --- Validation builder integration ---

  describe "validation builder" do
    test "returns {:ok, data} when all validations pass" do
      result =
        ValidationBuilder.new(%{name: "Alice", email: "alice@example.com"})
        |> ValidationBuilder.required(:name)
        |> ValidationBuilder.required(:email)
        |> ValidationBuilder.min_length(:name, 3)
        |> ValidationBuilder.build()

      assert {:ok, %{name: "Alice", email: "alice@example.com"}} = result
    end

    test "returns {:error, errors} when validations fail" do
      result =
        ValidationBuilder.new(%{name: "Al", email: nil})
        |> ValidationBuilder.required(:name)
        |> ValidationBuilder.required(:email)
        |> ValidationBuilder.min_length(:name, 3)
        |> ValidationBuilder.build()

      assert {:error, errors} = result
      assert {:email, "is required"} in errors
      assert {:name, "must be at least 3 characters"} in errors
    end

    test "returns {:ok, data} with no rules" do
      result =
        ValidationBuilder.new(%{anything: true})
        |> ValidationBuilder.build()

      assert {:ok, %{anything: true}} = result
    end

    test "catches missing required fields" do
      result =
        ValidationBuilder.new(%{})
        |> ValidationBuilder.required(:name)
        |> ValidationBuilder.build()

      assert {:error, [{:name, "is required"}]} = result
    end

    test "catches empty string as missing" do
      result =
        ValidationBuilder.new(%{name: ""})
        |> ValidationBuilder.required(:name)
        |> ValidationBuilder.build()

      assert {:error, [{:name, "is required"}]} = result
    end
  end

  # --- __using__ macro ---

  describe "__using__ macro" do
    test "injects @behaviour OmBehaviours.Builder" do
      behaviours =
        SimpleBuilder.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert OmBehaviours.Builder in behaviours
    end

    test "makes defcompose available" do
      # If defcompose wasn't imported, the module wouldn't compile
      # The existence of SimpleBuilder.multiply/2 proves it works
      assert function_exported?(SimpleBuilder, :multiply, 2)
      assert function_exported?(SimpleBuilder, :add, 2)
      assert function_exported?(SimpleBuilder, :negate, 1)
    end
  end
end
