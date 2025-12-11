defmodule OmMigration.FieldBuilders.StatusFields do
  @moduledoc """
  Builds status tracking fields for migrations.

  Status fields track the lifecycle state of records.

  ## Options

  - `:only` - List of fields to include
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: `:citext`)
  - `:null` - Whether fields can be null (default: `true`)
  - `:with_transition` - Include transition tracking fields (default: `false`)

  ## Available Fields

  - `:status` - Primary status
  - `:substatus` - Secondary status
  - `:state` - State machine state
  - `:workflow_state` - Workflow state
  - `:approval_status` - Approval status

  ## Transition Fields (when `with_transition: true`)

  - `:previous_status` - Previous status value
  - `:status_changed_at` - When status last changed
  - `:status_changed_by` - Who changed the status
  - `:status_history` - JSONB array of status changes

  ## Examples

      create_table(:orders)
      |> with_status_fields()
      |> with_status_fields(only: [:status])
      |> with_status_fields(with_transition: true)
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @all_fields [:status, :substatus, :state, :workflow_state, :approval_status]

  @impl true
  def default_config do
    %{
      type: :citext,
      null: true,
      with_transition: false,
      fields: @all_fields
    }
  end

  @impl true
  def build(token, config) do
    token
    |> add_status_fields(config)
    |> maybe_add_transition_fields(config)
  end

  @impl true
  def indexes(config) do
    base_indexes =
      config.fields
      |> Enum.map(fn field -> {:"#{field}_index", [field], []} end)

    case config.with_transition do
      true -> [{:status_changed_at_index, [:status_changed_at], []} | base_indexes]
      false -> base_indexes
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp add_status_fields(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_name, acc ->
      Token.add_field(acc, field_name, config.type,
        null: config.null,
        comment: "Status field: #{field_name}"
      )
    end)
  end

  defp maybe_add_transition_fields(token, %{with_transition: false}), do: token

  defp maybe_add_transition_fields(token, %{with_transition: true, type: type}) do
    token
    |> Token.add_field(:previous_status, type, null: true, comment: "Previous status value")
    |> Token.add_field(:status_changed_at, :utc_datetime_usec,
      null: true,
      comment: "When status last changed"
    )
    |> Token.add_field(:status_changed_by, :binary_id,
      null: true,
      comment: "Who changed the status"
    )
    |> Token.add_field(:status_history, :jsonb,
      default: [],
      null: false,
      comment: "History of status changes"
    )
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds status tracking fields to a migration token.
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
