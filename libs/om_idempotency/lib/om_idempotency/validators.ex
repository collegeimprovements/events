defmodule OmIdempotency.Validators do
  @moduledoc """
  Custom validators for idempotency records.

  Provides validation logic for TTL, state transitions, and other constraints.
  """

  import Ecto.Changeset

  @doc """
  Validates that the TTL (expires_at) is in the future.

  ## Examples

      changeset
      |> validate_ttl(:expires_at)
  """
  def validate_ttl(changeset, field) do
    validate_change(changeset, field, fn _, expires_at ->
      case DateTime.compare(expires_at, DateTime.utc_now()) do
        :gt -> []
        _ -> [{field, "must be in the future"}]
      end
    end)
  end

  @doc """
  Validates state transitions are valid.

  Valid transitions:
  - pending -> processing
  - processing -> completed
  - processing -> failed
  - processing -> pending (on release)

  Invalid transitions:
  - completed -> *
  - failed -> *
  - expired -> *
  """
  def validate_state_transition(changeset) do
    old_state = get_original_state(changeset)
    new_state = get_change(changeset, :state)

    case {old_state, new_state} do
      {nil, _} ->
        # New record, no transition
        changeset

      {same, same} ->
        # No state change
        changeset

      # Valid transitions
      {:pending, :processing} -> changeset
      {:processing, :completed} -> changeset
      {:processing, :failed} -> changeset
      {:processing, :pending} -> changeset

      # Invalid transitions
      {:completed, _} ->
        add_error(changeset, :state, "cannot transition from completed state")

      {:failed, _} ->
        add_error(changeset, :state, "cannot transition from failed state")

      {:expired, _} ->
        add_error(changeset, :state, "cannot transition from expired state")

      {old, new} ->
        add_error(changeset, :state, "invalid transition from #{old} to #{new}")
    end
  end

  @doc """
  Validates that the locked_until timestamp is in the future when processing.
  """
  def validate_locked_until(changeset) do
    state = get_field(changeset, :state)
    locked_until = get_change(changeset, :locked_until)

    case {state, locked_until} do
      {:processing, %DateTime{} = lu} ->
        if DateTime.compare(lu, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, :locked_until, "must be in the future for processing state")
        end

      _ ->
        changeset
    end
  end

  @doc """
  Validates that response is only set when state is completed.
  """
  def validate_response_state(changeset) do
    state = get_field(changeset, :state)
    response = get_change(changeset, :response)

    case {state, response} do
      {:completed, nil} ->
        add_error(changeset, :response, "must be set when state is completed")

      {state, %{}} when state != :completed ->
        add_error(changeset, :response, "can only be set when state is completed")

      _ ->
        changeset
    end
  end

  @doc """
  Validates that error is only set when state is failed.
  """
  def validate_error_state(changeset) do
    state = get_field(changeset, :state)
    error = get_change(changeset, :error)

    case {state, error} do
      {:failed, nil} ->
        add_error(changeset, :error, "must be set when state is failed")

      {state, %{}} when state != :failed ->
        add_error(changeset, :error, "can only be set when state is failed")

      _ ->
        changeset
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp get_original_state(changeset) do
    case get_field(changeset, :__meta__) do
      %Ecto.Schema.Metadata{state: :loaded} -> changeset.data.state
      _ -> nil
    end
  end
end
