defmodule OmScheduler.Store.MemoryTest do
  use ExUnit.Case

  alias OmScheduler.{Job, Execution}
  alias OmScheduler.Store.Memory
  alias OmScheduler.Workflow

  @tables [:scheduler_jobs_memory, :scheduler_executions_memory, :scheduler_locks_memory, :scheduler_workflows_memory]

  setup do
    # Ensure ETS tables exist
    ensure_tables_exist()
    # Clear tables between tests
    clear_tables()
    :ok
  end

  defp ensure_tables_exist do
    @tables
    |> Enum.each(fn table ->
      if :ets.whereis(table) == :undefined do
        :ets.new(table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])
      end
    end)
  end

  defp clear_tables do
    @tables
    |> Enum.each(fn table ->
      if :ets.whereis(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end)
  end

  describe "register_job/1" do
    test "successfully registers a new job" do
      job = build_job("test_job")
      assert {:ok, registered} = Memory.register_job(job)
      assert registered.name == "test_job"
    end

    test "returns error for duplicate job name" do
      job = build_job("duplicate_job")
      assert {:ok, _} = Memory.register_job(job)
      assert {:error, :already_exists} = Memory.register_job(job)
    end
  end

  describe "get_job/1" do
    test "returns job when it exists" do
      job = build_job("existing_job")
      {:ok, _} = Memory.register_job(job)

      assert {:ok, found} = Memory.get_job("existing_job")
      assert found.name == "existing_job"
    end

    test "returns error when job not found" do
      assert {:error, :not_found} = Memory.get_job("nonexistent")
    end
  end

  describe "list_jobs/1" do
    test "returns all jobs" do
      {:ok, _} = Memory.register_job(build_job("job_1"))
      {:ok, _} = Memory.register_job(build_job("job_2"))

      assert {:ok, jobs} = Memory.list_jobs()
      assert length(jobs) == 2
    end

    test "filters by queue" do
      {:ok, _} = Memory.register_job(build_job("job_1", queue: "default"))
      {:ok, _} = Memory.register_job(build_job("job_2", queue: "priority"))

      assert {:ok, jobs} = Memory.list_jobs(queue: "default")
      assert length(jobs) == 1
      assert hd(jobs).queue == "default"
    end

    test "filters by tags" do
      {:ok, _} = Memory.register_job(build_job("job_1", tags: ["important"]))
      {:ok, _} = Memory.register_job(build_job("job_2", tags: ["low"]))

      assert {:ok, jobs} = Memory.list_jobs(tags: ["important"])
      assert length(jobs) == 1
      assert "important" in hd(jobs).tags
    end

    test "supports pagination" do
      for i <- 1..10 do
        {:ok, _} = Memory.register_job(build_job("job_#{i}"))
      end

      assert {:ok, jobs} = Memory.list_jobs(limit: 3, offset: 0)
      assert length(jobs) == 3
    end
  end

  describe "update_job/2" do
    test "updates job attributes" do
      {:ok, _} = Memory.register_job(build_job("update_me"))

      assert {:ok, updated} = Memory.update_job("update_me", %{paused: true})
      assert updated.paused == true
    end

    test "returns error for nonexistent job" do
      assert {:error, :not_found} = Memory.update_job("nonexistent", %{paused: true})
    end
  end

  describe "delete_job/1" do
    test "deletes existing job" do
      {:ok, _} = Memory.register_job(build_job("delete_me"))
      assert :ok = Memory.delete_job("delete_me")
      assert {:error, :not_found} = Memory.get_job("delete_me")
    end
  end

  describe "get_due_jobs/2" do
    test "returns jobs that are due" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      {:ok, _} = Memory.register_job(build_job("due_job", next_run_at: past))
      {:ok, _} = Memory.register_job(build_job("future_job", next_run_at: future))

      assert {:ok, jobs} = Memory.get_due_jobs(DateTime.utc_now())
      assert length(jobs) == 1
      assert hd(jobs).name == "due_job"
    end

    test "excludes disabled jobs" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      {:ok, _} = Memory.register_job(build_job("disabled_job", next_run_at: past, enabled: false))

      assert {:ok, jobs} = Memory.get_due_jobs(DateTime.utc_now())
      assert jobs == []
    end

    test "excludes paused jobs" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      {:ok, _} = Memory.register_job(build_job("paused_job", next_run_at: past, paused: true))

      assert {:ok, jobs} = Memory.get_due_jobs(DateTime.utc_now())
      assert jobs == []
    end

    test "filters by queue" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      {:ok, _} = Memory.register_job(build_job("default_job", next_run_at: past, queue: "default"))
      {:ok, _} = Memory.register_job(build_job("priority_job", next_run_at: past, queue: "priority"))

      assert {:ok, jobs} = Memory.get_due_jobs(DateTime.utc_now(), queue: "default")
      assert length(jobs) == 1
      assert hd(jobs).name == "default_job"
    end

    test "respects limit" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      for i <- 1..10 do
        {:ok, _} = Memory.register_job(build_job("job_#{i}", next_run_at: past))
      end

      assert {:ok, jobs} = Memory.get_due_jobs(DateTime.utc_now(), limit: 3)
      assert length(jobs) == 3
    end
  end

  describe "mark_completed/3" do
    test "updates job after successful execution" do
      {:ok, _} = Memory.register_job(build_job("complete_me"))
      next_run = DateTime.add(DateTime.utc_now(), 60, :second)

      assert {:ok, updated} = Memory.mark_completed("complete_me", :ok, next_run)
      assert updated.run_count == 1
      assert updated.last_result == ":ok"
      assert updated.next_run_at == next_run
    end
  end

  describe "mark_failed/3" do
    test "updates job after failed execution" do
      {:ok, _} = Memory.register_job(build_job("fail_me"))
      next_run = DateTime.add(DateTime.utc_now(), 60, :second)

      assert {:ok, updated} = Memory.mark_failed("fail_me", :timeout, next_run)
      assert updated.error_count == 1
      assert updated.last_error == ":timeout"
    end
  end

  describe "acquire_unique_lock/3" do
    test "acquires lock when not held" do
      assert {:ok, "lock_key"} = Memory.acquire_unique_lock("lock_key", "owner1", 60_000)
    end

    test "returns error when lock is held" do
      {:ok, _} = Memory.acquire_unique_lock("lock_key", "owner1", 60_000)
      assert {:error, :locked} = Memory.acquire_unique_lock("lock_key", "owner2", 60_000)
    end

    test "allows acquiring expired lock" do
      # Acquire with 1ms TTL
      {:ok, _} = Memory.acquire_unique_lock("expiring_lock", "owner1", 1)
      Process.sleep(10)

      # Should be able to acquire now
      assert {:ok, _} = Memory.acquire_unique_lock("expiring_lock", "owner2", 60_000)
    end
  end

  describe "release_unique_lock/2" do
    test "releases lock held by owner" do
      {:ok, _} = Memory.acquire_unique_lock("release_key", "owner1", 60_000)
      assert :ok = Memory.release_unique_lock("release_key", "owner1")

      # Should be acquirable now
      assert {:ok, _} = Memory.acquire_unique_lock("release_key", "owner2", 60_000)
    end

    test "does not release lock held by different owner" do
      {:ok, _} = Memory.acquire_unique_lock("other_key", "owner1", 60_000)
      assert :ok = Memory.release_unique_lock("other_key", "wrong_owner")

      # Lock should still be held
      assert {:error, :locked} = Memory.acquire_unique_lock("other_key", "owner2", 60_000)
    end
  end

  describe "execution tracking" do
    test "records execution start" do
      execution = %Execution{
        id: nil,
        job_name: "test_job",
        started_at: DateTime.utc_now(),
        state: :running
      }

      assert {:ok, recorded} = Memory.record_execution_start(execution)
      assert recorded.id != nil
    end

    test "records execution complete" do
      execution = %Execution{
        id: Ecto.UUID.generate(),
        job_name: "test_job",
        started_at: DateTime.utc_now(),
        state: :completed,
        completed_at: DateTime.utc_now()
      }

      assert {:ok, _} = Memory.record_execution_complete(execution)
    end

    test "retrieves executions by job name" do
      execution = %Execution{
        id: Ecto.UUID.generate(),
        job_name: "tracked_job",
        started_at: DateTime.utc_now(),
        state: :completed
      }

      {:ok, _} = Memory.record_execution_start(execution)

      assert {:ok, executions} = Memory.get_executions("tracked_job")
      assert length(executions) == 1
    end
  end

  describe "bulk_update_jobs/2" do
    test "updates multiple jobs by queue" do
      {:ok, _} = Memory.register_job(build_job("sync_job_1", queue: "sync"))
      {:ok, _} = Memory.register_job(build_job("sync_job_2", queue: "sync"))
      {:ok, _} = Memory.register_job(build_job("default_job", queue: "default"))

      assert {:ok, 2} = Memory.bulk_update_jobs([queue: "sync"], %{paused: true})

      assert {:ok, job1} = Memory.get_job("sync_job_1")
      assert {:ok, job2} = Memory.get_job("sync_job_2")
      assert {:ok, job3} = Memory.get_job("default_job")

      assert job1.paused == true
      assert job2.paused == true
      assert job3.paused == false
    end

    test "updates jobs by name pattern" do
      {:ok, _} = Memory.register_job(build_job("report_daily"))
      {:ok, _} = Memory.register_job(build_job("report_weekly"))
      {:ok, _} = Memory.register_job(build_job("sync_users"))

      assert {:ok, 2} = Memory.bulk_update_jobs([name_pattern: "report_*"], %{max_retries: 10})

      assert {:ok, job1} = Memory.get_job("report_daily")
      assert {:ok, job2} = Memory.get_job("report_weekly")
      assert {:ok, job3} = Memory.get_job("sync_users")

      assert job1.max_retries == 10
      assert job2.max_retries == 10
      assert job3.max_retries == 3
    end

    test "updates jobs by specific names" do
      {:ok, _} = Memory.register_job(build_job("job_a"))
      {:ok, _} = Memory.register_job(build_job("job_b"))
      {:ok, _} = Memory.register_job(build_job("job_c"))

      assert {:ok, 2} = Memory.bulk_update_jobs([names: ["job_a", "job_c"]], %{timeout: 120_000})

      assert {:ok, job_a} = Memory.get_job("job_a")
      assert {:ok, job_b} = Memory.get_job("job_b")
      assert {:ok, job_c} = Memory.get_job("job_c")

      assert job_a.timeout == 120_000
      assert job_b.timeout == 60_000
      assert job_c.timeout == 120_000
    end

    test "updates jobs by tags" do
      {:ok, _} = Memory.register_job(build_job("critical_job", tags: ["critical", "sync"]))
      {:ok, _} = Memory.register_job(build_job("normal_job", tags: ["normal"]))
      {:ok, _} = Memory.register_job(build_job("tagged_job", tags: ["critical"]))

      assert {:ok, 2} = Memory.bulk_update_jobs([tags: ["critical"]], %{priority: 1})

      assert {:ok, j1} = Memory.get_job("critical_job")
      assert {:ok, j2} = Memory.get_job("normal_job")
      assert {:ok, j3} = Memory.get_job("tagged_job")

      assert j1.priority == 1
      assert j2.priority == 0
      assert j3.priority == 1
    end

    test "updates jobs by state" do
      {:ok, _} = Memory.register_job(build_job("active_job", state: :active))
      {:ok, _} = Memory.register_job(build_job("paused_job", state: :paused, paused: true))

      assert {:ok, 1} = Memory.bulk_update_jobs([state: :paused], %{state: :active, paused: false})

      assert {:ok, j1} = Memory.get_job("active_job")
      assert {:ok, j2} = Memory.get_job("paused_job")

      assert j1.state == :active
      assert j2.state == :active
      assert j2.paused == false
    end

    test "handles combined filters" do
      {:ok, _} = Memory.register_job(build_job("sync_job_1", queue: "sync", tags: ["critical"]))
      {:ok, _} = Memory.register_job(build_job("sync_job_2", queue: "sync", tags: ["normal"]))
      {:ok, _} = Memory.register_job(build_job("default_job", queue: "default", tags: ["critical"]))

      assert {:ok, 1} = Memory.bulk_update_jobs([queue: "sync", tags: ["critical"]], %{priority: 1})

      assert {:ok, j1} = Memory.get_job("sync_job_1")
      assert {:ok, j2} = Memory.get_job("sync_job_2")
      assert {:ok, j3} = Memory.get_job("default_job")

      assert j1.priority == 1
      assert j2.priority == 0
      assert j3.priority == 0
    end

    test "returns zero when no jobs match" do
      {:ok, _} = Memory.register_job(build_job("some_job"))

      assert {:ok, 0} = Memory.bulk_update_jobs([queue: "nonexistent"], %{paused: true})
    end
  end

  describe "count_jobs/1" do
    test "counts jobs by filter" do
      {:ok, _} = Memory.register_job(build_job("sync_1", queue: "sync"))
      {:ok, _} = Memory.register_job(build_job("sync_2", queue: "sync"))
      {:ok, _} = Memory.register_job(build_job("default_1", queue: "default"))

      assert {:ok, 2} = Memory.count_jobs(queue: "sync")
      assert {:ok, 1} = Memory.count_jobs(queue: "default")
      assert {:ok, 3} = Memory.count_jobs([])
    end

    test "counts jobs by name pattern" do
      {:ok, _} = Memory.register_job(build_job("report_daily"))
      {:ok, _} = Memory.register_job(build_job("report_weekly"))
      {:ok, _} = Memory.register_job(build_job("sync_users"))

      assert {:ok, 2} = Memory.count_jobs(name_pattern: "report_*")
      assert {:ok, 1} = Memory.count_jobs(name_pattern: "sync_*")
      assert {:ok, 0} = Memory.count_jobs(name_pattern: "nonexistent_*")
    end

    test "counts paused jobs" do
      {:ok, _} = Memory.register_job(build_job("active_job", paused: false))
      {:ok, _} = Memory.register_job(build_job("paused_job", paused: true))

      assert {:ok, 1} = Memory.count_jobs(paused: true)
      assert {:ok, 1} = Memory.count_jobs(paused: false)
    end
  end

  describe "workflow operations" do
    test "registers workflow" do
      workflow = build_workflow(:test_workflow)
      assert {:ok, registered} = Memory.register_workflow(workflow)
      assert registered.name == :test_workflow
    end

    test "returns error for duplicate workflow" do
      workflow = build_workflow(:duplicate_workflow)
      {:ok, _} = Memory.register_workflow(workflow)
      assert {:error, :already_exists} = Memory.register_workflow(workflow)
    end

    test "retrieves workflow by name" do
      workflow = build_workflow(:find_me)
      {:ok, _} = Memory.register_workflow(workflow)

      assert {:ok, found} = Memory.get_workflow(:find_me)
      assert found.name == :find_me
    end

    test "lists workflows" do
      {:ok, _} = Memory.register_workflow(build_workflow(:wf_1))
      {:ok, _} = Memory.register_workflow(build_workflow(:wf_2))

      workflows = Memory.list_workflows()
      assert length(workflows) == 2
    end

    test "deletes workflow" do
      {:ok, _} = Memory.register_workflow(build_workflow(:delete_me))
      assert :ok = Memory.delete_workflow(:delete_me)
      assert {:error, :not_found} = Memory.get_workflow(:delete_me)
    end
  end

  # Helpers

  defp build_job(name, opts \\ []) do
    %Job{
      name: name,
      module: "MyApp.Worker",
      function: "perform",
      args: %{},
      schedule_type: :interval,
      schedule: %{every: 60_000},
      timezone: "Etc/UTC",
      enabled: Keyword.get(opts, :enabled, true),
      paused: Keyword.get(opts, :paused, false),
      state: Keyword.get(opts, :state, :active),
      queue: Keyword.get(opts, :queue, "default"),
      priority: Keyword.get(opts, :priority, 0),
      max_retries: Keyword.get(opts, :max_retries, 3),
      timeout: Keyword.get(opts, :timeout, 60_000),
      tags: Keyword.get(opts, :tags, []),
      next_run_at: Keyword.get(opts, :next_run_at),
      run_count: 0,
      error_count: 0
    }
  end

  defp build_workflow(name) do
    %Workflow{
      name: name,
      steps: %{},
      adjacency: %{},
      execution_order: [],
      trigger_type: :manual,
      state: :enabled,
      tags: []
    }
  end
end
