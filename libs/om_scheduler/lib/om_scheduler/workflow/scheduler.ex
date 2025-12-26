defmodule OmScheduler.Workflow.Scheduler do
  @moduledoc """
  Scheduler plugin for workflow cron and interval-based execution.

  Periodically checks for workflows that are due to run based on their schedule
  configuration and starts workflow executions.

  Only runs on the leader node.

  ## Configuration

      config :om_scheduler,
        plugins: [
          {OmScheduler.Workflow.Scheduler,
            interval: {1, :minute},
            limit: 50}
        ]

  ## Options

  - `:interval` - How often to check for due workflows (default: 1 minute)
  - `:limit` - Max workflows to schedule per tick (default: 50)
  """

  use GenServer
  require Logger

  alias OmScheduler.Config
  alias OmScheduler.Workflow.{Registry, Store, Engine}

  @behaviour OmScheduler.Plugin

  @default_interval 60_000
  @default_limit 50

  # ============================================
  # Plugin Callbacks
  # ============================================

  @impl OmScheduler.Plugin
  def validate(opts) do
    with true <- is_nil(opts[:interval]) or Config.valid_duration?(opts[:interval]),
         true <- is_nil(opts[:limit]) or (is_integer(opts[:limit]) and opts[:limit] > 0) do
      :ok
    else
      _ -> {:error, "invalid Workflow.Scheduler plugin options"}
    end
  end

  @impl OmScheduler.Plugin
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())

    state = %{
      name: Keyword.get(opts, :name, __MODULE__),
      interval: Config.to_ms(opts[:interval] || @default_interval),
      limit: opts[:limit] || @default_limit,
      peer: conf[:peer],
      conf: conf,
      scheduled_count: 0,
      last_run: nil,
      # Track last run time for each workflow
      schedule_state: %{}
    }

    # Schedule first tick
    schedule_tick(state.interval)

    Logger.info("[Workflow.Scheduler] Started with interval=#{state.interval}ms")

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    new_state =
      case Config.leader?(state.peer) do
        true -> schedule_due_workflows(state)
        false -> state
      end

    schedule_tick(state.interval)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      scheduled_count: state.scheduled_count,
      last_run: state.last_run,
      interval: state.interval,
      limit: state.limit,
      schedule_state: state.schedule_state
    }

    {:reply, stats, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp schedule_due_workflows(state) do
    now = DateTime.utc_now()

    # Get all registered workflows with schedules
    workflows = get_scheduled_workflows()

    # Filter to workflows that are due
    due_workflows =
      workflows
      |> Enum.filter(fn workflow -> workflow_due?(workflow, now, state.schedule_state) end)
      |> Enum.take(state.limit)

    # Start executions for due workflows
    {scheduled, new_schedule_state} =
      Enum.reduce(due_workflows, {0, state.schedule_state}, fn workflow, {count, sched_state} ->
        case start_workflow_execution(workflow) do
          {:ok, _exec_id} ->
            new_sched_state = Map.put(sched_state, workflow.name, now)
            {count + 1, new_sched_state}

          {:error, reason} ->
            Logger.warning(
              "[Workflow.Scheduler] Failed to start workflow #{workflow.name}: #{inspect(reason)}"
            )

            {count, sched_state}
        end
      end)

    if scheduled > 0 do
      Logger.debug("[Workflow.Scheduler] Started #{scheduled} workflow executions")
    end

    %{
      state
      | scheduled_count: state.scheduled_count + scheduled,
        last_run: now,
        schedule_state: new_schedule_state
    }
  end

  defp get_scheduled_workflows do
    # Try Registry first (faster, in-memory)
    registry_workflows =
      try do
        Registry.list_workflows(trigger_type: :scheduled)
      catch
        :exit, _ -> []
      end

    # Also check database Store for persisted workflows
    store_workflows =
      case Store.list_workflows(trigger_type: :scheduled) do
        workflows when is_list(workflows) ->
          # Convert schema records to workflow structs if needed
          Enum.map(workflows, fn
            %OmScheduler.Workflow{} = w -> w
            schema -> schema
          end)

        _ ->
          []
      end

    # Merge and dedupe by name (prefer Registry)
    registry_names = MapSet.new(registry_workflows, & &1.name)

    store_only =
      Enum.reject(store_workflows, fn w ->
        MapSet.member?(registry_names, w.name)
      end)

    registry_workflows ++ store_only
  end

  defp workflow_due?(workflow, now, schedule_state) do
    schedule = workflow.schedule

    cond do
      # Cron schedule
      Keyword.has_key?(schedule, :cron) ->
        cron_due?(workflow, now, schedule_state)

      # Interval schedule
      Keyword.has_key?(schedule, :every) ->
        interval_due?(workflow, now, schedule_state)

      # One-time at specific time
      Keyword.has_key?(schedule, :at) ->
        at_due?(schedule, now, schedule_state, workflow.name)

      # One-time relative delay
      Keyword.has_key?(schedule, :in) ->
        # :in schedules are handled at registration time, not by scheduler
        false

      true ->
        false
    end
  end

  defp cron_due?(workflow, now, schedule_state) do
    cron_expr = Keyword.get(workflow.schedule, :cron)
    last_run = Map.get(schedule_state, workflow.name)

    cron_exprs = if is_list(cron_expr), do: cron_expr, else: [cron_expr]

    Enum.any?(cron_exprs, fn expr ->
      case parse_cron(expr) do
        {:ok, parsed} ->
          # Check if we should run now based on cron
          matches_cron?(parsed, now) and should_run_since_last?(last_run, now)

        {:error, _} ->
          false
      end
    end)
  end

  defp interval_due?(workflow, now, schedule_state) do
    {amount, unit} = Keyword.get(workflow.schedule, :every)
    interval_ms = Config.to_ms({amount, unit})
    last_run = Map.get(schedule_state, workflow.name)

    # Check start/end bounds if specified
    start_at = Keyword.get(workflow.schedule, :start_at)
    end_at = Keyword.get(workflow.schedule, :end_at)

    in_bounds = within_bounds?(now, start_at, end_at)

    in_bounds and (last_run == nil or DateTime.diff(now, last_run, :millisecond) >= interval_ms)
  end

  defp at_due?(schedule, now, schedule_state, workflow_name) do
    at = Keyword.get(schedule, :at)
    last_run = Map.get(schedule_state, workflow_name)

    # Only run once at the specified time
    # Within 1 minute window
    last_run == nil and
      DateTime.compare(now, at) in [:eq, :gt] and
      DateTime.diff(now, at, :second) < 60
  end

  defp within_bounds?(_now, nil, nil), do: true
  defp within_bounds?(now, start_at, nil), do: DateTime.compare(now, start_at) != :lt
  defp within_bounds?(now, nil, end_at), do: DateTime.compare(now, end_at) != :gt

  defp within_bounds?(now, start_at, end_at) do
    DateTime.compare(now, start_at) != :lt and DateTime.compare(now, end_at) != :gt
  end

  defp should_run_since_last?(nil, _now), do: true

  defp should_run_since_last?(last_run, now) do
    # Ensure at least 1 minute has passed since last run
    DateTime.diff(now, last_run, :second) >= 60
  end

  defp parse_cron(cron_string) do
    # Simple cron parser for minute hour day month weekday
    # Format: "minute hour day month weekday"
    # e.g., "0 6 * * *" = daily at 6 AM
    # e.g., "*/5 * * * *" = every 5 minutes
    # e.g., "0 9-17 * * 1-5" = 9 AM - 5 PM on weekdays

    parts = String.split(cron_string, ~r/\s+/)

    case parts do
      [minute, hour, day, month, weekday] ->
        {:ok,
         %{
           minute: parse_cron_field(minute, 0..59),
           hour: parse_cron_field(hour, 0..23),
           day: parse_cron_field(day, 1..31),
           month: parse_cron_field(month, 1..12),
           weekday: parse_cron_field(weekday, 0..6)
         }}

      _ ->
        {:error, :invalid_cron_format}
    end
  end

  defp parse_cron_field("*", _range), do: :all
  # Treat invalid */X as all
  defp parse_cron_field("*/", _range), do: :all

  defp parse_cron_field(field, range) do
    cond do
      # Step pattern: */N
      String.starts_with?(field, "*/") ->
        step = String.trim_leading(field, "*/") |> String.to_integer()
        {:step, step}

      # Range pattern: N-M
      String.contains?(field, "-") ->
        [from, to] = String.split(field, "-") |> Enum.map(&String.to_integer/1)
        {:range, from, to}

      # List pattern: N,M,O
      String.contains?(field, ",") ->
        values = String.split(field, ",") |> Enum.map(&String.to_integer/1)
        {:list, values}

      # Single value
      true ->
        case Integer.parse(field) do
          {num, ""} ->
            if num in Enum.to_list(range), do: {:value, num}, else: :all

          _ ->
            :all
        end
    end
  rescue
    _ -> :all
  end

  defp matches_cron?(cron, now) do
    matches_field?(cron.minute, now.minute) and
      matches_field?(cron.hour, now.hour) and
      matches_field?(cron.day, now.day) and
      matches_field?(cron.month, now.month) and
      matches_field?(cron.weekday, Date.day_of_week(now) |> rem(7))
  end

  defp matches_field?(:all, _value), do: true
  defp matches_field?({:value, expected}, value), do: expected == value
  defp matches_field?({:step, step}, value), do: rem(value, step) == 0
  defp matches_field?({:range, from, to}, value), do: value >= from and value <= to
  defp matches_field?({:list, values}, value), do: value in values

  defp start_workflow_execution(workflow) do
    Logger.info("[Workflow.Scheduler] Starting scheduled execution of workflow #{workflow.name}")

    case Engine.start_workflow(workflow.name, %{
           __trigger__: :scheduled,
           __scheduled_at__: DateTime.utc_now()
         }) do
      {:ok, exec_id} ->
        # Note: Telemetry is already emitted by Engine.init/1
        {:ok, exec_id}

      error ->
        error
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
