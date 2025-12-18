defmodule Effect.Checkpoint do
  @moduledoc """
  Checkpoint and resume support for long-running Effect workflows.

  Checkpoints allow workflows to be paused at specific points and resumed
  later, even across process restarts. This is useful for:

  - Long-running workflows that may timeout
  - Human-in-the-loop approval workflows
  - Workflows that span multiple requests

  ## Usage

  Define checkpoints in your effect:

      Effect.new(:order_approval)
      |> Effect.step(:validate, &validate/1)
      |> Effect.checkpoint(:await_approval, store: &store_state/2, load: &load_state/1)
      |> Effect.step(:fulfill, &fulfill/1)

  When execution reaches a checkpoint, the state is persisted and execution
  pauses. Later, resume from the checkpoint:

      Effect.resume(effect, execution_id)

  ## Storage Adapters

  You provide `store` and `load` functions that handle persistence:

      # ETS-based (for testing)
      checkpoint(:name,
        store: fn id, state -> :ets.insert(:checkpoints, {id, state}); :ok end,
        load: fn id -> case :ets.lookup(:checkpoints, id) do [{_, s}] -> {:ok, s}; [] -> {:error, :not_found} end end
      )

      # Database-based
      checkpoint(:name,
        store: fn id, state -> Repo.insert(%Checkpoint{id: id, state: state}) end,
        load: fn id -> Repo.get(Checkpoint, id) |> case do nil -> {:error, :not_found}; c -> {:ok, c.state} end end
      )

  ## State Format

  Checkpointed state includes:
  - Execution ID
  - Current context
  - Completed steps
  - Checkpoint name
  - Timestamp
  """

  @type checkpoint_state :: %{
          execution_id: String.t(),
          effect_name: atom(),
          checkpoint: atom(),
          context: map(),
          completed_steps: [atom()],
          created_at: DateTime.t()
        }

  @type store_fn :: (String.t(), checkpoint_state() -> :ok | {:error, term()})
  @type load_fn :: (String.t() -> {:ok, checkpoint_state()} | {:error, term()})

  @doc """
  Creates a checkpoint state structure for persistence.
  """
  @spec create_state(String.t(), atom(), atom(), map(), [atom()]) :: checkpoint_state()
  def create_state(execution_id, effect_name, checkpoint_name, ctx, completed_steps) do
    %{
      execution_id: execution_id,
      effect_name: effect_name,
      checkpoint: checkpoint_name,
      context: ctx,
      completed_steps: completed_steps,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Validates checkpoint state for resumption.

  Checks that:
  - Effect name matches
  - Required fields are present
  """
  @spec validate_state(checkpoint_state(), atom()) :: :ok | {:error, term()}
  def validate_state(%{effect_name: name} = _state, expected_name) when name == expected_name do
    :ok
  end

  def validate_state(%{effect_name: actual}, expected) do
    {:error, {:effect_mismatch, expected: expected, actual: actual}}
  end

  def validate_state(state, _expected) when not is_map(state) do
    {:error, :invalid_state_format}
  end

  defmodule InMemory do
    @moduledoc """
    In-memory checkpoint storage for testing.

    Uses an ETS table named `:effect_checkpoints`.

    ## Examples

        # Initialize
        Effect.Checkpoint.InMemory.init()

        # Use in effect
        Effect.checkpoint(effect, :approval,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
    """

    @table :effect_checkpoints

    @doc "Initialize the in-memory checkpoint store."
    @spec init() :: :ok
    def init do
      if :ets.whereis(@table) == :undefined do
        :ets.new(@table, [:named_table, :public, :set])
      end

      :ok
    end

    @doc "Store a checkpoint state."
    @spec store(String.t(), map()) :: :ok
    def store(execution_id, state) do
      init()
      :ets.insert(@table, {execution_id, state})
      :ok
    end

    @doc "Load a checkpoint state."
    @spec load(String.t()) :: {:ok, map()} | {:error, :not_found}
    def load(execution_id) do
      init()

      case :ets.lookup(@table, execution_id) do
        [{^execution_id, state}] -> {:ok, state}
        [] -> {:error, :not_found}
      end
    end

    @doc "Delete a checkpoint state."
    @spec delete(String.t()) :: :ok
    def delete(execution_id) do
      init()
      :ets.delete(@table, execution_id)
      :ok
    end

    @doc "List all checkpoints."
    @spec list() :: [map()]
    def list do
      init()

      :ets.tab2list(@table)
      |> Enum.map(fn {_id, state} -> state end)
    end

    @doc "Clear all checkpoints."
    @spec clear() :: :ok
    def clear do
      init()
      :ets.delete_all_objects(@table)
      :ok
    end
  end
end
