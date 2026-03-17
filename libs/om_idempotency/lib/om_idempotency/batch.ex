defmodule OmIdempotency.Batch do
  @moduledoc """
  Batch operations for idempotency records using OmCrud.

  Provides efficient bulk operations for creating, updating, and managing
  multiple idempotency records at once.
  """

  alias OmIdempotency.Record
  alias OmCrud
  alias OmCrud.Multi
  alias FnTypes.{Result, AsyncResult}

  @doc """
  Creates multiple idempotency records in a single transaction.

  ## Examples

      Batch.create_all([
        {"order_123_charge", scope: "stripe", metadata: %{order_id: 123}},
        {"order_124_charge", scope: "stripe", metadata: %{order_id: 124}}
      ])
  """
  @spec create_all([{String.t(), keyword()}], keyword()) ::
          {:ok, [Record.t()]} | {:error, term()}
  def create_all(key_opts_pairs, global_opts \\ []) do
    ttl = Keyword.get(global_opts, :ttl, 24 * 60 * 60 * 1000)

    entries =
      Enum.map(key_opts_pairs, fn {key, opts} ->
        scope = Keyword.get(opts, :scope)
        metadata = Keyword.get(opts, :metadata, %{})
        record_ttl = Keyword.get(opts, :ttl, ttl)

        %{
          key: key,
          scope: scope,
          state: :pending,
          metadata: metadata,
          expires_at: DateTime.add(DateTime.utc_now(), record_ttl, :millisecond),
          inserted_at: {:placeholder, :now},
          updated_at: {:placeholder, :now}
        }
      end)

    placeholders = %{now: DateTime.utc_now()}

    OmCrud.create_all(
      Record,
      entries,
      Keyword.merge(global_opts,
        placeholders: placeholders,
        on_conflict: :nothing,
        conflict_target: [:key, :scope]
      )
    )
  end

  @doc """
  Completes multiple records with their responses.

  Uses a transaction to ensure atomicity.

  ## Examples

      Batch.complete_all([
        {record1, response1},
        {record2, response2}
      ])
  """
  @spec complete_all([{Record.t(), term()}], keyword()) ::
          {:ok, map()} | {:error, term()}
  def complete_all(record_response_pairs, opts \\ []) do
    multi =
      record_response_pairs
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {{record, response}, idx}, multi ->
        Multi.update(
          multi,
          {:complete, idx},
          record,
          %{state: :completed, response: serialize_response(response), completed_at: DateTime.utc_now()},
          changeset: :complete_changeset
        )
      end)

    OmCrud.run(multi, opts)
  end

  @doc """
  Fails multiple records with their errors.

  ## Examples

      Batch.fail_all([
        {record1, error1},
        {record2, error2}
      ])
  """
  @spec fail_all([{Record.t(), term()}], keyword()) :: {:ok, map()} | {:error, term()}
  def fail_all(record_error_pairs, opts \\ []) do
    multi =
      record_error_pairs
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {{record, error}, idx}, multi ->
        Multi.update(
          multi,
          {:fail, idx},
          record,
          %{state: :failed, error: serialize_error(error), completed_at: DateTime.utc_now()},
          changeset: :fail_changeset
        )
      end)

    OmCrud.run(multi, opts)
  end

  @doc """
  Checks multiple idempotency keys in parallel.

  Returns results in the same order as input keys.

  ## Examples

      Batch.check_many([
        {"order_123", "stripe"},
        {"order_124", "stripe"}
      ])
      #=> {:ok, [
        {:ok, %Record{}},
        {:error, :not_found}
      ]}
  """
  @spec check_many([{String.t(), String.t() | nil}], keyword()) ::
          {:ok, [Result.t(Record.t())]}
  def check_many(key_scope_pairs, opts \\ []) do
    tasks =
      Enum.map(key_scope_pairs, fn {key, scope} ->
        fn -> OmIdempotency.get(key, scope, opts) end
      end)

    case AsyncResult.parallel(tasks) do
      {:ok, results} -> {:ok, results}
      {:error, _} = error -> error
    end
  end

  @doc """
  Executes multiple operations in parallel with idempotency protection.

  Each operation gets its own idempotency key and is executed concurrently.

  ## Examples

      Batch.execute_all([
        {"key1", fn -> expensive_op1() end, [scope: "api"]},
        {"key2", fn -> expensive_op2() end, [scope: "api"]}
      ])
  """
  @spec execute_all([{String.t(), function(), keyword()}], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def execute_all(operations, global_opts \\ []) do
    tasks =
      Enum.map(operations, fn {key, fun, opts} ->
        fn ->
          OmIdempotency.execute(
            key,
            fun,
            Keyword.merge(global_opts, opts)
          )
        end
      end)

    AsyncResult.parallel(tasks)
  end

  @doc """
  Releases multiple processing locks in a single transaction.

  ## Examples

      Batch.release_all([record1, record2, record3])
  """
  @spec release_all([Record.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def release_all(records, opts \\ []) do
    multi =
      records
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {record, idx}, multi ->
        Multi.update(
          multi,
          {:release, idx},
          record,
          %{state: :pending, locked_until: nil, started_at: nil},
          changeset: :release_changeset
        )
      end)

    OmCrud.run(multi, opts)
  end

  @doc """
  Deletes multiple records by their IDs in bulk.

  ## Examples

      Batch.delete_by_ids([id1, id2, id3])
  """
  @spec delete_by_ids([Ecto.UUID.t()], keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete_by_ids(ids, opts \\ []) do
    import Ecto.Query

    query = from(r in Record, where: r.id in ^ids)

    case OmIdempotency.repo(opts).delete_all(query) do
      {count, _} -> {:ok, count}
      error -> error
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp serialize_response({:ok, data}), do: %{ok: data}
  defp serialize_response(data), do: data

  defp serialize_error(%{__struct__: module} = error) do
    %{
      type: Kernel.inspect(module),
      message: Exception.message(error),
      details: Map.from_struct(error)
    }
  end

  defp serialize_error(error) when is_atom(error),
    do: %{type: "atom", message: Atom.to_string(error)}

  defp serialize_error(error) when is_binary(error),
    do: %{type: "string", message: error}

  defp serialize_error(error),
    do: %{type: "unknown", message: Kernel.inspect(error)}
end
