defmodule OmSchema.TestHelpers do
  @moduledoc """
  Test helpers for OmSchema validation testing.

  Provides utilities to test field validations in isolation without
  requiring a full schema setup.

  ## Usage

      use ExUnit.Case
      import OmSchema.TestHelpers

      test "email validation" do
        assert_valid("test@example.com", :string, format: :email)
        assert_invalid("not-an-email", :string, format: :email)
      end
  """

  import ExUnit.Assertions
  alias OmSchema.ValidationPipeline

  @doc """
  Test a single field validation without a full schema.

  Returns the changeset for further assertions.
  """
  @spec validate_field(any(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_field(value, type, opts) do
    data = %{}
    types = %{test_field: type}

    changeset =
      {data, types}
      |> Ecto.Changeset.cast(%{test_field: value}, [:test_field])

    ValidationPipeline.validate_field(changeset, :test_field, type, opts)
  end

  @doc """
  Assert that a value is valid for the given type and options.
  """
  @spec assert_valid(any(), atom(), keyword()) :: Ecto.Changeset.t()
  def assert_valid(value, type, opts) do
    changeset = validate_field(value, type, opts)

    assert changeset.valid?,
           "Expected #{inspect(value)} to be valid, but got errors: #{inspect(changeset.errors)}"

    changeset
  end

  @doc """
  Assert that a value is invalid for the given type and options.
  """
  @spec assert_invalid(any(), atom(), keyword()) :: Ecto.Changeset.t()
  def assert_invalid(value, type, opts) do
    changeset = validate_field(value, type, opts)

    refute changeset.valid?,
           "Expected #{inspect(value)} to be invalid, but it was valid"

    changeset
  end

  @doc """
  Assert that a value produces a specific error message.
  """
  @spec assert_error(any(), atom(), keyword(), String.t() | Regex.t()) :: Ecto.Changeset.t()
  def assert_error(value, type, opts, expected_message) do
    changeset = assert_invalid(value, type, opts)
    errors = errors_on(changeset)

    assert Map.has_key?(errors, :test_field),
           "No errors found for test_field"

    field_errors = errors[:test_field]

    found =
      case expected_message do
        %Regex{} = regex ->
          Enum.any?(field_errors, &String.match?(&1, regex))

        message ->
          message in field_errors
      end

    assert found,
           "Expected error message #{inspect(expected_message)} not found in #{inspect(field_errors)}"

    changeset
  end

  @doc """
  Assert that a value does not produce any errors.
  """
  @spec assert_no_errors(any(), atom(), keyword()) :: Ecto.Changeset.t()
  def assert_no_errors(value, type, opts) do
    changeset = validate_field(value, type, opts)
    errors = errors_on(changeset)

    assert errors == %{},
           "Expected no errors, but got: #{inspect(errors)}"

    changeset
  end

  @doc """
  Test multiple values against the same validation.
  """
  @spec test_values([any()], atom(), keyword(), boolean()) :: :ok
  def test_values(values, type, opts, expected_valid) do
    Enum.each(values, fn value ->
      if expected_valid do
        assert_valid(value, type, opts)
      else
        assert_invalid(value, type, opts)
      end
    end)
  end

  @doc """
  Test that valid values pass and invalid values fail.
  """
  @spec test_validation(keyword()) :: :ok
  def test_validation(opts) do
    valid_values = Keyword.get(opts, :valid, [])
    invalid_values = Keyword.get(opts, :invalid, [])
    type = Keyword.fetch!(opts, :type)
    validation_opts = Keyword.fetch!(opts, :opts)

    test_values(valid_values, type, validation_opts, true)
    test_values(invalid_values, type, validation_opts, false)
  end

  @doc """
  Create a test schema module with given fields for integration testing.
  """
  @spec create_test_schema(keyword()) :: module()
  def create_test_schema(fields) do
    module_name = :"TestSchema#{System.unique_integer([:positive])}"

    ast =
      quote do
        use OmSchema

        schema "test_table" do
          (unquote_splicing(
             Enum.map(fields, fn {name, type, opts} ->
               quote do
                 field(unquote(name), unquote(type), unquote(opts))
               end
             end)
           ))
        end

        def changeset(schema, attrs) do
          schema
          |> Ecto.Changeset.cast(attrs, __cast_fields__())
          |> Ecto.Changeset.validate_required(__required_fields__())
          |> __apply_field_validations__()
        end
      end

    Module.create(module_name, ast, Macro.Env.location(__ENV__))
    module_name
  end

  @doc """
  Test normalization in isolation.
  """
  @spec test_normalization(String.t(), keyword() | atom() | function()) :: String.t()
  def test_normalization(value, opts) when is_list(opts) do
    OmSchema.Helpers.Normalizer.normalize(value, opts)
  end

  def test_normalization(value, normalizer) do
    # Wrap non-list normalizers in opts format
    OmSchema.Helpers.Normalizer.normalize(value, normalize: normalizer)
  end

  @doc """
  Test cross-field validation.
  """
  @spec test_cross_field(map(), [tuple()]) :: Ecto.Changeset.t()
  def test_cross_field(data, validations) do
    types = Map.new(data, fn {k, v} -> {k, type_for_value(v)} end)

    changeset =
      {%{}, types}
      |> Ecto.Changeset.cast(data, Map.keys(data))

    OmSchema.Validators.CrossField.validate(changeset, validations)
  end

  # Helper to extract errors from changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # Infer type from value
  defp type_for_value(value) do
    cond do
      is_binary(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_map(value) -> :map
      is_list(value) -> {:array, :string}
      true -> :string
    end
  end

  @doc """
  Benchmark validation performance.
  """
  @spec benchmark_validation(any(), atom(), keyword(), keyword()) :: :ok
  def benchmark_validation(value, type, opts, bench_opts \\ []) do
    iterations = Keyword.get(bench_opts, :iterations, 10_000)
    warmup = Keyword.get(bench_opts, :warmup, 100)

    # Warmup
    for _ <- 1..warmup do
      validate_field(value, type, opts)
    end

    # Benchmark
    start = System.monotonic_time()

    for _ <- 1..iterations do
      validate_field(value, type, opts)
    end

    stop = System.monotonic_time()
    duration = System.convert_time_unit(stop - start, :native, :microsecond)
    avg = duration / iterations

    IO.puts("Validation benchmark:")
    IO.puts("  Total: #{duration}μs for #{iterations} iterations")
    IO.puts("  Average: #{Float.round(avg, 2)}μs per validation")

    :ok
  end
end
