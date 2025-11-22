defmodule Events.Schema.Improved.PerformanceOptimizations do
  @moduledoc """
  Performance optimizations for Events.Schema.

  This module demonstrates performance improvements that could be applied
  to the validation system.
  """

  defmodule CompiledValidatorLookup do
    @moduledoc """
    Compile-time validator lookup instead of runtime pattern matching.

    Current approach uses multiple function clauses with pattern matching.
    This could be optimized with compile-time lookup tables.
    """
    @validators %{
      string: Events.Schema.Validators.String,
      citext: Events.Schema.Validators.String,
      integer: Events.Schema.Validators.Number,
      float: Events.Schema.Validators.Number,
      decimal: Events.Schema.Validators.Number,
      boolean: Events.Schema.Validators.Boolean,
      date: Events.Schema.Validators.DateTime,
      time: Events.Schema.Validators.DateTime,
      naive_datetime: Events.Schema.Validators.DateTime,
      utc_datetime: Events.Schema.Validators.DateTime
    }

    # Generate pattern matching functions at compile time
    for {type, validator} <- @validators do
      def get_validator(unquote(type)), do: unquote(validator)
    end

    # Fallback
    def get_validator({:array, _}), do: Events.Schema.Validators.Array
    def get_validator({:map, _}), do: Events.Schema.Validators.Map
    def get_validator(_), do: nil
  end

  defmodule CachedOptions do
    @moduledoc """
    Optimized option extraction using ETS for frequently accessed validations.
    """
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def init(_) do
      # Create ETS table for fast concurrent reads
      :ets.new(:validation_cache, [:named_table, :public, read_concurrency: true])
      {:ok, %{}}
    end

    def get_or_compute(key, fun) do
      case :ets.lookup(:validation_cache, key) do
        [{^key, value}] ->
          value

        [] ->
          value = fun.()
          :ets.insert(:validation_cache, {key, value})
          value
      end
    end
  end

  defmodule CompiledFormats do
    @moduledoc """
    Optimized regex compilation for format validations.

    Compiles regex patterns at compile time instead of runtime.
    """
    @formats %{
      email: ~r/@/,
      url: ~r/^https?:\/\//,
      uuid: ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      slug: ~r/^[a-z0-9-]+$/,
      hex_color: ~r/^#[0-9a-f]{6}$/i,
      ip: ~r/^(\d{1,3}\.){3}\d{1,3}$/
    }

    # Generate getter functions at compile time
    for {format, regex} <- @formats do
      def get_regex(unquote(format)), do: unquote(Macro.escape(regex))
    end

    def get_regex(_), do: nil
  end

  defmodule BatchValidator do
    @moduledoc """
    Batch validation for multiple fields of the same type.

    Reduces overhead when validating many fields with similar rules.
    """
    def validate_batch(changeset, fields_by_type) do
      Enum.reduce(fields_by_type, changeset, fn {type, fields}, acc ->
        validate_type_batch(acc, type, fields)
      end)
    end

    defp validate_type_batch(changeset, type, fields) do
      # Get validator for type
      validator_module = CompiledValidatorLookup.get_validator(type)

      if validator_module != nil and is_atom(validator_module) do
        # Apply to all fields using the validator module
        Enum.reduce(fields, changeset, fn {field, opts}, acc ->
          apply(validator_module, :validate, [acc, field, opts])
        end)
      else
        # No validator for this type, return unchanged
        changeset
      end
    end
  end

  defmodule LazyValidator do
    @moduledoc """
    Lazy validation - only validate changed fields.

    Skips validation for fields that haven't changed.
    """
    import Ecto.Changeset

    def validate_if_changed(changeset, field, validator) do
      if get_change(changeset, field) do
        validator.(changeset, field)
      else
        changeset
      end
    end

    def validate_changed_fields(changeset, field_specs) do
      changed_fields =
        changeset.changes
        |> Map.keys()
        |> MapSet.new()

      field_specs
      |> Enum.filter(fn {field, _, _} -> MapSet.member?(changed_fields, field) end)
      |> Enum.reduce(changeset, fn {field, type, opts}, acc ->
        Events.Schema.ValidationPipeline.validate_field(acc, field, type, opts)
      end)
    end
  end

  defmodule OptimizedMessages do
    @moduledoc """
    Optimized message building using iodata instead of string concatenation.
    """
    def build_message(template, params) do
      template
      |> build_iodata(params)
      |> IO.iodata_to_binary()
    end

    defp build_iodata(template, params) do
      Regex.split(~r/%{(\w+)}/, template, include_captures: true)
      |> Enum.map(fn
        "%{" <> rest ->
          key = String.trim_trailing(rest, "}")
          params[String.to_atom(key)] || ""

        part ->
          part
      end)
    end
  end

  defmodule ResultPool do
    @moduledoc """
    Validation result pooling to reduce memory allocation.

    Reuses validation result structures.
    """
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def init(_) do
      {:ok, %{pool: []}}
    end

    def checkout do
      GenServer.call(__MODULE__, :checkout)
    end

    def checkin(result) do
      GenServer.cast(__MODULE__, {:checkin, result})
    end

    def handle_call(:checkout, _from, %{pool: [result | rest]} = state) do
      {:reply, result, %{state | pool: rest}}
    end

    def handle_call(:checkout, _from, state) do
      # Create new result if pool is empty
      {:reply, %{errors: [], valid?: true}, state}
    end

    def handle_cast({:checkin, result}, %{pool: pool} = state) do
      # Clear and return to pool
      cleaned = %{result | errors: [], valid?: true}
      {:noreply, %{state | pool: [cleaned | pool]}}
    end
  end

  defmodule FailFastValidator do
    @moduledoc """
    Short-circuit validation on first error for fail-fast scenarios.
    """
    def validate(changeset, validations, opts \\ []) do
      fail_fast? = Keyword.get(opts, :fail_fast, false)

      if fail_fast? do
        validate_fail_fast(changeset, validations)
      else
        validate_all(changeset, validations)
      end
    end

    defp validate_fail_fast(changeset, validations) do
      Enum.reduce_while(validations, changeset, fn validation, acc ->
        result = validation.(acc)

        if result.valid? do
          {:cont, result}
        else
          {:halt, result}
        end
      end)
    end

    defp validate_all(changeset, validations) do
      Enum.reduce(validations, changeset, fn validation, acc ->
        validation.(acc)
      end)
    end
  end
end
