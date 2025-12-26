defmodule OmScheduler.Unique do
  @moduledoc """
  Enhanced unique job enforcement.

  Prevents duplicate job executions with flexible matching options.

  ## Options

  - `:unique` - Enable uniqueness (boolean or options)
  - `:unique_by` - Fields to include in uniqueness key
  - `:unique_states` - Only prevent if existing job is in these states
  - `:unique_period` - Time window for uniqueness (jobs older are ignored)

  ## Usage

      # Simple: prevent any concurrent execution
      @decorate scheduled(cron: @hourly, unique: true)
      def sync_data, do: ...

      # Unique by queue and args
      @decorate scheduled(
        cron: @hourly,
        unique: [
          by: [:queue, :args],
          states: [:running, :scheduled],
          period: {1, :hour}
        ]
      )
      def process_item(args), do: ...

  ## Unique By Options

  - `:name` - Job name (default, always included)
  - `:queue` - Queue name
  - `:args` - Job arguments (or specific arg keys)
  - `:worker` - Worker module

  ## Unique States

  - `:running` - Job is currently executing
  - `:scheduled` - Job is scheduled to run
  - `:retrying` - Job is waiting for retry

  ## Examples

      # Unique per user_id argument
      unique: [by: [:name, {:args, [:user_id]}]]

      # Only if currently running (allow if scheduled)
      unique: [states: [:running]]

      # Within last hour only
      unique: [period: {1, :hour}]
  """

  alias OmScheduler.{Job, Config}

  @type unique_opts :: boolean() | keyword()
  @type unique_key :: String.t()

  @default_states [:running]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Builds a unique key for a job based on its unique options.

  Returns `nil` if uniqueness is not enabled.
  """
  @spec build_key(Job.t() | map()) :: unique_key() | nil
  def build_key(%{unique: false}), do: nil
  def build_key(%{unique: nil}), do: nil

  def build_key(%{unique: true} = job) do
    # Simple uniqueness: just by name
    build_key_from_fields(job, [:name])
  end

  def build_key(%{unique: opts} = job) when is_list(opts) do
    by = Keyword.get(opts, :by, [:name])
    build_key_from_fields(job, by)
  end

  def build_key(_job), do: nil

  @doc """
  Checks if a job should be considered unique (blocked) given current state.

  Returns:
  - `:ok` - Job can proceed
  - `{:error, :unique_conflict}` - Job is blocked by existing execution
  """
  @spec check(Job.t() | map(), module()) :: :ok | {:error, :unique_conflict}
  def check(job, store) do
    case build_key(job) do
      nil ->
        :ok

      key ->
        opts = normalize_opts(job.unique)
        states = Keyword.get(opts, :states, @default_states)
        period = Keyword.get(opts, :period)

        do_check(key, states, period, store)
    end
  end

  @doc """
  Acquires a unique lock for a job.

  Returns:
  - `{:ok, key}` - Lock acquired
  - `{:error, :unique_conflict}` - Could not acquire (conflict)
  """
  @spec acquire(Job.t() | map(), module(), atom()) ::
          {:ok, unique_key()} | {:error, :unique_conflict}
  def acquire(job, store, node) do
    case build_key(job) do
      nil ->
        {:ok, nil}

      key ->
        opts = normalize_opts(job.unique)
        ttl = calculate_ttl(job, opts)

        case store.acquire_unique_lock(key, to_string(node), ttl) do
          {:ok, ^key} -> {:ok, key}
          {:error, :locked} -> {:error, :unique_conflict}
        end
    end
  end

  @doc """
  Releases a unique lock for a job.
  """
  @spec release(Job.t() | map(), module(), atom()) :: :ok
  def release(job, store, node) do
    case build_key(job) do
      nil -> :ok
      key -> store.release_unique_lock(key, to_string(node))
    end
  end

  @doc """
  Parses unique options from decorator/job config.

  Normalizes different input formats to a consistent keyword list.
  """
  @spec parse_opts(term()) :: keyword()
  def parse_opts(true), do: [enabled: true, by: [:name], states: @default_states]
  def parse_opts(false), do: [enabled: false]
  def parse_opts(nil), do: [enabled: false]

  def parse_opts(opts) when is_list(opts) do
    [
      enabled: true,
      by: Keyword.get(opts, :by, [:name]),
      states: Keyword.get(opts, :states, @default_states),
      period: Keyword.get(opts, :period)
    ]
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_opts(true), do: []
  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(_), do: []

  defp build_key_from_fields(job, fields) do
    parts =
      fields
      |> Enum.map(&extract_field(job, &1))
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      parts -> Enum.join(parts, ":")
    end
  end

  defp extract_field(job, :name), do: Map.get(job, :name)
  defp extract_field(job, :queue), do: Map.get(job, :queue)
  defp extract_field(job, :worker), do: Map.get(job, :module)

  defp extract_field(job, :args) do
    case Map.get(job, :args) do
      nil -> nil
      args when map_size(args) == 0 -> nil
      args -> hash_args(args)
    end
  end

  defp extract_field(job, {:args, keys}) when is_list(keys) do
    args = Map.get(job, :args, %{})

    subset =
      keys
      |> Enum.map(fn key ->
        {key, Map.get(args, key) || Map.get(args, to_string(key))}
      end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    case map_size(subset) do
      0 -> nil
      _ -> hash_args(subset)
    end
  end

  defp extract_field(job, field) when is_atom(field) do
    Map.get(job, field)
  end

  defp extract_field(_job, _field), do: nil

  defp hash_args(args) do
    args
    |> :erlang.term_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp do_check(key, states, period, store) do
    # Check if there's a conflicting execution
    cutoff = calculate_cutoff(period)

    case store.check_unique_conflict(key, states, cutoff) do
      {:ok, false} -> :ok
      {:ok, true} -> {:error, :unique_conflict}
      # If store doesn't support this, fall back to lock-based
      {:error, :not_implemented} -> :ok
    end
  rescue
    # If the callback doesn't exist, fall back to :ok
    UndefinedFunctionError -> :ok
  end

  defp calculate_cutoff(nil), do: nil

  defp calculate_cutoff(period) do
    ms = Config.to_ms(period)
    DateTime.add(DateTime.utc_now(), -ms, :millisecond)
  end

  defp calculate_ttl(job, opts) do
    case Keyword.get(opts, :period) do
      nil -> Map.get(job, :timeout, 60_000)
      period -> Config.to_ms(period)
    end
  end
end
