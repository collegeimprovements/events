defmodule OmScheduler.JobTest do
  @moduledoc """
  Tests for OmScheduler.Job - Scheduled job definition and management.

  Job encapsulates all configuration for a scheduled task including
  schedule type (cron/interval/reboot), retry behavior, and state tracking.

  ## Use Cases

  - **Cron jobs**: Run at specific times ("0 6 * * *" = daily at 6 AM)
  - **Interval jobs**: Run every N seconds/minutes/hours
  - **Reboot jobs**: Run once on application startup
  - **Job control**: Enable, pause, set priority and retries

  ## Pattern: Job Configuration

      Job.new(%{
        name: "daily_report",
        module: "MyApp.ReportWorker",
        function: "generate",
        cron: "0 6 * * *",           # Daily at 6 AM
        queue: "reports",
        max_retries: 3,
        timeout: 120_000
      })

      # Or with decorator:
      @decorate scheduled(cron: "0 6 * * *", queue: :reports)
      def generate, do: ...

  Job tracks: next_run_at, last_run_at, run_count, fail_count, state.
  """

  use ExUnit.Case, async: true

  alias OmScheduler.Job

  describe "new/1" do
    test "creates a job with required fields" do
      attrs = %{
        name: "test_job",
        module: "MyApp.Worker",
        function: "perform",
        every: {5, :minutes}
      }

      assert {:ok, job} = Job.new(attrs)
      assert job.name == "test_job"
      assert job.module == "MyApp.Worker"
      assert job.function == "perform"
    end

    test "accepts module as atom and converts to string" do
      attrs = %{
        name: "test_job",
        module: MyApp.Worker,
        function: :perform,
        every: {5, :minutes}
      }

      assert {:ok, job} = Job.new(attrs)
      assert job.module == "Elixir.MyApp.Worker"
      assert job.function == "perform"
    end

    test "applies default values" do
      attrs = %{
        name: "test_job",
        module: "MyApp.Worker",
        function: "perform",
        every: {5, :minutes}
      }

      assert {:ok, job} = Job.new(attrs)
      assert job.enabled == true
      assert job.paused == false
      assert job.state == :active
      assert job.queue == "default"
      assert job.priority == 0
      assert job.max_retries == 3
      assert job.timeout == 60_000
    end

    test "parses cron schedule" do
      attrs = %{
        name: "cron_job",
        module: "MyApp.Worker",
        function: "perform",
        cron: "0 6 * * *"
      }

      assert {:ok, job} = Job.new(attrs)
      assert job.schedule_type == :cron
      assert job.schedule[:expressions] == ["0 6 * * *"]
    end

    test "parses interval schedule" do
      attrs = %{
        name: "interval_job",
        module: "MyApp.Worker",
        function: "perform",
        every: {5, :minutes}
      }

      assert {:ok, job} = Job.new(attrs)
      assert job.schedule_type == :interval
      assert job.schedule[:every] == 300_000
    end

    test "validates name format" do
      attrs = %{
        name: "Invalid-Name",
        module: "MyApp.Worker",
        function: "perform",
        every: {5, :minutes}
      }

      assert {:error, changeset} = Job.new(attrs)
      assert "must be lowercase alphanumeric with underscores" in errors_on(changeset).name
    end

    test "validates priority range" do
      attrs = %{
        name: "test_job",
        module: "MyApp.Worker",
        function: "perform",
        every: {5, :minutes},
        priority: 100
      }

      assert {:error, changeset} = Job.new(attrs)
      assert errors_on(changeset).priority != []
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Job.new(%{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.module
      assert "can't be blank" in errors.function
    end
  end

  describe "new!/1" do
    test "returns job on success" do
      attrs = %{
        name: "test_job",
        module: "MyApp.Worker",
        function: "perform",
        every: {5, :minutes}
      }

      job = Job.new!(attrs)
      assert job.name == "test_job"
    end

    test "raises on invalid attrs" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Job.new!(%{})
      end
    end
  end

  describe "runnable?/1" do
    test "returns true when enabled, not paused, and active" do
      job = %Job{enabled: true, paused: false, state: :active}
      assert Job.runnable?(job) == true
    end

    test "returns false when disabled" do
      job = %Job{enabled: false, paused: false, state: :active}
      assert Job.runnable?(job) == false
    end

    test "returns false when paused" do
      job = %Job{enabled: true, paused: true, state: :active}
      assert Job.runnable?(job) == false
    end

    test "returns false when not active" do
      job = %Job{enabled: true, paused: false, state: :paused}
      assert Job.runnable?(job) == false
    end
  end

  describe "due?/2" do
    test "returns false when next_run_at is nil" do
      job = %Job{next_run_at: nil}
      assert Job.due?(job, DateTime.utc_now()) == false
    end

    test "returns true when next_run_at is in the past" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      job = %Job{next_run_at: past}
      assert Job.due?(job, DateTime.utc_now()) == true
    end

    test "returns true when next_run_at equals now" do
      now = DateTime.utc_now()
      job = %Job{next_run_at: now}
      assert Job.due?(job, now) == true
    end

    test "returns false when next_run_at is in the future" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)
      job = %Job{next_run_at: future}
      assert Job.due?(job, DateTime.utc_now()) == false
    end
  end

  describe "reboot?/1" do
    test "returns true for reboot schedule type" do
      job = %Job{schedule_type: :reboot}
      assert Job.reboot?(job) == true
    end

    test "returns false for other schedule types" do
      assert Job.reboot?(%Job{schedule_type: :cron}) == false
      assert Job.reboot?(%Job{schedule_type: :interval}) == false
    end
  end

  describe "calculate_next_run/2" do
    test "returns error for reboot jobs" do
      job = %Job{schedule_type: :reboot}
      assert {:error, :no_next_run} = Job.calculate_next_run(job, DateTime.utc_now())
    end

    test "calculates next run for interval jobs" do
      now = DateTime.utc_now()
      job = %Job{schedule_type: :interval, schedule: %{every: 60_000}}

      assert {:ok, next} = Job.calculate_next_run(job, now)
      diff = DateTime.diff(next, now, :millisecond)
      assert diff == 60_000
    end

    test "calculates next run for cron jobs" do
      # Use a time that's not at the start of a minute
      now = ~U[2024-01-10 10:30:15Z]
      job = %Job{
        schedule_type: :cron,
        schedule: %{expressions: ["* * * * *"]},
        timezone: "Etc/UTC"
      }

      assert {:ok, next} = Job.calculate_next_run(job, now)
      # Should be at the next minute
      assert next.minute == 31 or next.minute == 30
    end
  end

  describe "from_decorator_opts/3" do
    test "builds job attrs from decorator options" do
      attrs = Job.from_decorator_opts(MyApp.Worker, :perform, [
        cron: "0 6 * * *",
        queue: :priority,
        max_retries: 5
      ])

      assert attrs.module == "Elixir.MyApp.Worker"
      assert attrs.function == "perform"
      assert attrs.schedule_type == :cron
      assert attrs.queue == "priority"
      assert attrs.max_retries == 5
    end

    test "generates name from module and function" do
      attrs = Job.from_decorator_opts(MyApp.Worker, :perform, [])
      assert attrs.name == "elixir_myapp_worker_perform"
    end

    test "uses custom name if provided" do
      attrs = Job.from_decorator_opts(MyApp.Worker, :perform, name: "custom_job")
      assert attrs.name == "custom_job"
    end
  end

  # Helper to extract error messages from changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
