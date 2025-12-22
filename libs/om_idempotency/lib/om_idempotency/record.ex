defmodule OmIdempotency.Record do
  @moduledoc """
  Schema for storing idempotency records.

  Tracks the state and response of idempotent operations to prevent
  duplicate execution on retries.

  ## Fields

  - `key` - The idempotency key (unique within scope)
  - `scope` - Optional scope/namespace (e.g., "stripe", "sendgrid")
  - `state` - Current state: pending, processing, completed, failed, expired
  - `version` - Optimistic locking version
  - `response` - Cached successful response (JSON)
  - `error` - Error details for failed operations (JSON)
  - `metadata` - Additional metadata (JSON)
  - `started_at` - When processing started
  - `completed_at` - When operation completed
  - `locked_until` - Lock expiration for processing state
  - `expires_at` - When this record should be cleaned up

  ## State Machine

      pending -> processing -> completed
                     |
                     +------> failed
                     |
                     +------> pending (on release)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type state :: :pending | :processing | :completed | :failed | :expired

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          key: String.t(),
          scope: String.t() | nil,
          state: state(),
          version: integer(),
          response: map() | nil,
          error: map() | nil,
          metadata: map(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          locked_until: DateTime.t() | nil,
          expires_at: DateTime.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "idempotency_records" do
    field :key, :string
    field :scope, :string

    field :state, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed, :expired],
      default: :pending

    field :version, :integer, default: 1

    field :response, :map
    field :error, :map
    field :metadata, :map, default: %{}

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :locked_until, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a new idempotency record.
  """
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:key, :scope, :state, :metadata, :expires_at])
    |> validate_required([:key, :expires_at])
    |> unique_constraint([:key, :scope], name: :idempotency_records_key_scope_index)
  end

  @doc """
  Changeset for transitioning to processing state.
  """
  def processing_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :started_at, :locked_until, :version])
    |> validate_required([:state, :started_at, :locked_until])
    |> optimistic_lock(:version)
  end

  @doc """
  Changeset for marking as completed with response.
  """
  def complete_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :response, :completed_at])
    |> validate_required([:state, :completed_at])
    |> validate_inclusion(:state, [:completed])
  end

  @doc """
  Changeset for marking as failed with error.
  """
  def fail_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :error, :completed_at])
    |> validate_required([:state, :completed_at])
    |> validate_inclusion(:state, [:failed])
  end

  @doc """
  Changeset for releasing a processing lock.
  """
  def release_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :locked_until, :started_at])
    |> validate_inclusion(:state, [:pending])
  end

  # ============================================
  # Query Helpers
  # ============================================

  @doc """
  Returns true if the record is in a terminal state.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}) when state in [:completed, :failed, :expired], do: true
  def terminal?(%__MODULE__{}), do: false

  @doc """
  Returns true if the record can be retried.
  """
  @spec retriable?(t()) :: boolean()
  def retriable?(%__MODULE__{state: :pending}), do: true

  def retriable?(%__MODULE__{state: :processing, locked_until: locked_until}) do
    DateTime.compare(locked_until, DateTime.utc_now()) == :lt
  end

  def retriable?(%__MODULE__{}), do: false

  @doc """
  Returns true if the record has expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end
end
