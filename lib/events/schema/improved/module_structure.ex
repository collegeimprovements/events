defmodule Events.Schema.Improved.ModuleStructure do
  @moduledoc ~S"""
  Proposed improved module organization for Events.Schema.

  This module demonstrates a better organization structure that could be
  applied to the Events.Schema system for improved maintainability.

  Suggested module hierarchy:

  Events.Schema/
  ├── Core/
  │   ├── Field.ex           # Field definition and metadata
  │   ├── Schema.ex          # Main schema macro
  │   └── Types.ex           # Type specifications
  │
  ├── Validation/
  │   ├── Pipeline.ex        # Main validation orchestrator
  │   ├── Registry.ex        # Validator registration and lookup
  │   ├── Result.ex          # Validation result handling
  │   │
  │   ├── Types/             # Type-specific validators
  │   │   ├── String.ex
  │   │   ├── Number.ex
  │   │   ├── Boolean.ex
  │   │   ├── DateTime.ex
  │   │   ├── Array.ex
  │   │   └── Map.ex
  │   │
  │   ├── Rules/             # Validation rules
  │   │   ├── Length.ex      # Length validations
  │   │   ├── Format.ex      # Format validations
  │   │   ├── Range.ex       # Range validations
  │   │   ├── Inclusion.ex   # Inclusion/exclusion
  │   │   └── Comparison.ex  # Comparison validations
  │   │
  │   └── Constraints/       # Database constraints
  │       ├── Unique.ex
  │       ├── ForeignKey.ex
  │       └── Check.ex
  │
  ├── Normalization/
  │   ├── Pipeline.ex        # Normalization orchestrator
  │   ├── Transformers.ex    # Individual transformers
  │   └── Slugify.ex        # Special slug handling
  │
  ├── Presets/
  │   ├── Registry.ex        # Preset registration
  │   ├── Basic.ex          # Basic field presets
  │   ├── Financial.ex      # Financial field presets
  │   ├── Network.ex        # Network field presets
  │   ├── Geographic.ex     # Location field presets
  │   └── Social.ex         # Social media presets
  │
  ├── Introspection/
  │   ├── Schema.ex         # Schema introspection
  │   ├── Field.ex          # Field introspection
  │   └── JsonSchema.ex     # JSON Schema generation
  │
  ├── Testing/
  │   ├── Helpers.ex        # Test helpers
  │   ├── Assertions.ex     # Custom assertions
  │   └── Factories.ex      # Test data factories
  │
  ├── Telemetry/
  │   ├── Events.ex         # Event definitions
  │   ├── Handlers.ex       # Default handlers
  │   └── Metrics.ex        # Metric collection
  │
  ├── Errors/
  │   ├── Handler.ex        # Error handling
  │   ├── Formatter.ex      # Error formatting
  │   └── Priority.ex       # Error prioritization
  │
  └── Utils/
      ├── Messages.ex       # Message handling
      ├── Conditional.ex    # Conditional logic
      └── Warnings.ex       # Compile-time warnings
  """

  defmodule ValidatorRegistry do
    @moduledoc """
    Central registry for validators with dynamic registration.
    """

    use GenServer

    # Client API
    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def register(type, validator) do
      GenServer.call(__MODULE__, {:register, type, validator})
    end

    def get_validator(type) do
      GenServer.call(__MODULE__, {:get_validator, type})
    end

    # Server callbacks
    def init(_) do
      validators = %{
        string: Events.Schema.Validators.String,
        integer: Events.Schema.Validators.Number,
        float: Events.Schema.Validators.Number,
        decimal: Events.Schema.Validators.Number,
        boolean: Events.Schema.Validators.Boolean
      }

      {:ok, validators}
    end

    def handle_call({:register, type, validator}, _from, validators) do
      {:reply, :ok, Map.put(validators, type, validator)}
    end

    def handle_call({:get_validator, type}, _from, validators) do
      {:reply, Map.get(validators, type), validators}
    end
  end

  defmodule PresetCategory do
    @moduledoc """
    Base behaviour for preset categories.
    """

    @callback presets() :: map()
    @callback preset(atom()) :: keyword()

    defmacro __using__(_) do
      quote do
        @behaviour Events.Schema.Improved.ModuleStructure.PresetCategory

        def get(name) do
          presets()[name] || raise "Unknown preset: #{name}"
        end

        def list do
          Map.keys(presets())
        end

        defoverridable get: 1, list: 0
      end
    end
  end

  defmodule ValidationRule do
    @moduledoc """
    Base behaviour for validation rules.
    """

    @callback validate(Ecto.Changeset.t(), atom(), any(), keyword()) :: Ecto.Changeset.t()
    @callback applicable?(atom(), keyword()) :: boolean()

    defmacro __using__(opts) do
      rule_type = Keyword.fetch!(opts, :type)

      quote do
        @behaviour Events.Schema.Improved.ModuleStructure.ValidationRule
        @rule_type unquote(rule_type)

        def applicable?(field_type, opts) do
          field_type in applicable_types() && has_required_options?(opts)
        end

        defp applicable_types do
          case @rule_type do
            :string -> [:string, :citext]
            :number -> [:integer, :float, :decimal]
            :datetime -> [:date, :time, :naive_datetime, :utc_datetime]
            :universal -> :all
            _ -> []
          end
        end

        defp has_required_options?(opts) do
          required_options()
          |> Enum.any?(fn key -> Keyword.has_key?(opts, key) end)
        end

        defp required_options, do: []

        defoverridable applicable?: 2, applicable_types: 0, required_options: 0
      end
    end
  end

  defmodule PipelineComposer do
    @moduledoc """
    Composes validation pipelines dynamically.
    """

    def compose(validators) do
      fn changeset, field, opts ->
        validators
        |> filter_applicable(field, opts)
        |> apply_validators(changeset, field, opts)
      end
    end

    defp filter_applicable(validators, field, opts) do
      Enum.filter(validators, fn validator ->
        validator.applicable?(field, opts)
      end)
    end

    defp apply_validators(validators, changeset, field, opts) do
      Enum.reduce(validators, changeset, fn validator, acc ->
        validator.validate(acc, field, opts)
      end)
    end
  end
end
