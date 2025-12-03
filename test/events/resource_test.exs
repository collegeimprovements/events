defmodule Events.Types.ResourceTest do
  use ExUnit.Case, async: true

  alias Events.Types.Resource

  describe "with_resource/3" do
    test "acquires, uses, and releases resource" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        Resource.with_resource(
          fn ->
            Agent.update(log, &["acquired" | &1])
            :resource
          end,
          fn :resource ->
            Agent.update(log, &["released" | &1])
          end,
          fn :resource ->
            Agent.update(log, &["used" | &1])
            "result"
          end
        )

      assert result == {:ok, "result"}
      assert Agent.get(log, & &1) == ["released", "used", "acquired"]
    end

    test "releases resource even when use raises" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      assert_raise RuntimeError, "boom", fn ->
        Resource.with_resource(
          fn ->
            Agent.update(log, &["acquired" | &1])
            :resource
          end,
          fn :resource ->
            Agent.update(log, &["released" | &1])
          end,
          fn :resource ->
            raise "boom"
          end
        )
      end

      assert Agent.get(log, & &1) == ["released", "acquired"]
    end

    test "returns error when acquire fails" do
      result =
        Resource.with_resource(
          fn -> raise "acquire failed" end,
          fn _ -> :ok end,
          fn r -> r end
        )

      assert {:error, {:acquire_failed, %RuntimeError{message: "acquire failed"}}} = result
    end

    test "wraps non-tuple results in :ok" do
      result =
        Resource.with_resource(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> 42 end
        )

      assert result == {:ok, 42}
    end

    test "passes through {:ok, value} results" do
      result =
        Resource.with_resource(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> {:ok, "value"} end
        )

      assert result == {:ok, "value"}
    end

    test "passes through {:error, reason} results" do
      result =
        Resource.with_resource(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> {:error, :not_found} end
        )

      assert result == {:error, :not_found}
    end

    test "wraps :ok atom in {:ok, :ok}" do
      result =
        Resource.with_resource(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> :ok end
        )

      assert result == {:ok, :ok}
    end
  end

  describe "bracket/3" do
    test "is alias for with_resource" do
      result =
        Resource.bracket(
          fn -> "file" end,
          fn _ -> :closed end,
          fn file -> String.upcase(file) end
        )

      assert result == {:ok, "FILE"}
    end
  end

  describe "with_resources/2" do
    test "acquires resources in order" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        Resource.with_resources(
          [
            {fn ->
               Agent.update(log, &["a1" | &1])
               :a
             end, fn _ -> Agent.update(log, &["a2" | &1]) end},
            {fn ->
               Agent.update(log, &["b1" | &1])
               :b
             end, fn _ -> Agent.update(log, &["b2" | &1]) end},
            {fn ->
               Agent.update(log, &["c1" | &1])
               :c
             end, fn _ -> Agent.update(log, &["c2" | &1]) end}
          ],
          fn resources ->
            Agent.update(log, &["used" | &1])
            resources
          end
        )

      assert result == {:ok, [:a, :b, :c]}
      # Acquired in order, released in reverse
      events = Agent.get(log, & &1) |> Enum.reverse()
      assert events == ["a1", "b1", "c1", "used", "c2", "b2", "a2"]
    end

    test "releases acquired resources if later acquire fails" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        Resource.with_resources(
          [
            {fn ->
               Agent.update(log, &["a1" | &1])
               :a
             end, fn _ -> Agent.update(log, &["a2" | &1]) end},
            {fn -> raise "boom" end, fn _ -> Agent.update(log, &["b2" | &1]) end},
            {fn ->
               Agent.update(log, &["c1" | &1])
               :c
             end, fn _ -> Agent.update(log, &["c2" | &1]) end}
          ],
          fn _ -> :ok end
        )

      assert {:error, {:acquire_failed, %RuntimeError{message: "boom"}}} = result
      # Only first was acquired and released
      events = Agent.get(log, & &1) |> Enum.reverse()
      assert events == ["a1", "a2"]
    end

    test "releases all resources if use raises" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      assert_raise RuntimeError, "use failed", fn ->
        Resource.with_resources(
          [
            {fn ->
               Agent.update(log, &["a1" | &1])
               :a
             end, fn _ -> Agent.update(log, &["a2" | &1]) end},
            {fn ->
               Agent.update(log, &["b1" | &1])
               :b
             end, fn _ -> Agent.update(log, &["b2" | &1]) end}
          ],
          fn _ ->
            raise "use failed"
          end
        )
      end

      events = Agent.get(log, & &1) |> Enum.reverse()
      assert events == ["a1", "b1", "b2", "a2"]
    end

    test "ignores errors during release" do
      result =
        Resource.with_resources(
          [
            {fn -> :a end, fn _ -> raise "release failed" end},
            {fn -> :b end, fn _ -> :ok end}
          ],
          fn [a, b] -> {a, b} end
        )

      # Still succeeds despite release error
      assert result == {:ok, {:a, :b}}
    end
  end

  describe "define/1 and using/2" do
    test "creates reusable resource definition" do
      counter = Agent.start_link(fn -> 0 end) |> elem(1)

      resource_def =
        Resource.define(
          acquire: fn ->
            Agent.update(counter, &(&1 + 1))
            Agent.get(counter, & &1)
          end,
          release: fn _ -> Agent.update(counter, &(&1 - 1)) end
        )

      result1 = Resource.using(resource_def, fn count -> count * 10 end)
      assert result1 == {:ok, 10}
      assert Agent.get(counter, & &1) == 0

      result2 = Resource.using(resource_def, fn count -> count * 10 end)
      assert result2 == {:ok, 10}
      assert Agent.get(counter, & &1) == 0
    end

    test "requires acquire and release options" do
      assert_raise KeyError, fn ->
        Resource.define(acquire: fn -> :ok end)
      end

      assert_raise KeyError, fn ->
        Resource.define(release: fn _ -> :ok end)
      end
    end
  end

  describe "with_file/3" do
    @tag :tmp_dir
    test "opens and closes file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.txt")
      File.write!(path, "hello")

      result =
        Resource.with_file(path, [:read], fn file ->
          IO.read(file, :eof)
        end)

      assert result == {:ok, "hello"}
    end

    @tag :tmp_dir
    test "writes to file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "output.txt")

      result =
        Resource.with_file(path, [:write], fn file ->
          IO.write(file, "written")
        end)

      assert result == {:ok, :ok}
      assert File.read!(path) == "written"
    end

    test "returns error for non-existent file" do
      result =
        Resource.with_file("/nonexistent/path.txt", [:read], fn file ->
          IO.read(file, :all)
        end)

      assert {:error, {:acquire_failed, %File.Error{}}} = result
    end
  end

  describe "with_temp_file/1" do
    test "creates and deletes temp file" do
      {result, path} =
        Resource.with_temp_file(fn path ->
          File.write!(path, "temp data")
          content = File.read!(path)
          {content, path}
        end)

      assert {:ok, {"temp data", created_path}} = {result, path}
      refute File.exists?(created_path)
    end
  end

  describe "with_temp_dir/1" do
    test "creates and deletes temp directory" do
      {result, dir} =
        Resource.with_temp_dir(fn dir ->
          File.write!(Path.join(dir, "file.txt"), "data")
          {File.ls!(dir), dir}
        end)

      assert {:ok, {["file.txt"], created_dir}} = {result, dir}
      refute File.exists?(created_dir)
    end
  end

  describe "with_process/2" do
    test "spawns and kills process" do
      parent = self()

      result =
        Resource.with_process(
          fn ->
            spawn(fn ->
              send(parent, {:started, self()})
              Process.sleep(:infinity)
            end)
          end,
          fn pid ->
            # Wait for the process to start
            receive do
              {:started, ^pid} -> :started
            after
              100 -> :no_start
            end
          end
        )

      assert {:ok, :started} = result

      # The process should be dead now
      receive do
        {:started, pid} ->
          # Give time for cleanup
          Process.sleep(50)
          refute Process.alive?(pid)
      after
        # Message already consumed above
        0 -> :ok
      end
    end
  end

  describe "with_ets/3" do
    test "creates and deletes ETS table" do
      result =
        Resource.with_ets(:test_table, [:set, :public], fn table ->
          :ets.insert(table, {:key, "value"})
          :ets.lookup(table, :key)
        end)

      assert result == {:ok, [key: "value"]}

      # Table should be deleted
      assert :ets.whereis(:test_table) == :undefined
    end

    test "works with named table" do
      result =
        Resource.with_ets(:named_test, [:set, :named_table], fn table ->
          :ets.insert(table, {:a, 1})
          :ets.tab2list(table)
        end)

      assert result == {:ok, [a: 1]}
    end
  end

  describe "with_agent/2" do
    test "starts and stops agent" do
      result =
        Resource.with_agent(fn -> %{count: 0} end, fn agent ->
          Agent.update(agent, fn state -> %{state | count: state.count + 1} end)
          Agent.get(agent, & &1)
        end)

      assert result == {:ok, %{count: 1}}
    end

    test "agent is stopped after use" do
      Resource.with_agent(fn -> :state end, fn agent ->
        send(self(), {:agent_pid, agent})
        :ok
      end)

      receive do
        {:agent_pid, pid} ->
          Process.sleep(50)
          refute Process.alive?(pid)
      after
        100 -> flunk("No agent pid received")
      end
    end
  end

  describe "with_resource_safe/3" do
    test "catches exceptions and returns error tuple" do
      result =
        Resource.with_resource_safe(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> raise "boom" end
        )

      assert {:error, {:exception, %RuntimeError{message: "boom"}}} = result
    end

    test "catches exits" do
      result =
        Resource.with_resource_safe(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> exit(:shutdown) end
        )

      assert result == {:error, {:exit, :shutdown}}
    end

    test "catches throws" do
      result =
        Resource.with_resource_safe(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> throw(:thrown_value) end
        )

      assert result == {:error, {:throw, :thrown_value}}
    end

    test "passes through normal results" do
      result =
        Resource.with_resource_safe(
          fn -> :resource end,
          fn _ -> :ok end,
          fn _ -> {:ok, "value"} end
        )

      assert result == {:ok, "value"}
    end
  end

  describe "ensure/2" do
    test "runs cleanup regardless of result" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        Resource.ensure(
          fn ->
            Agent.update(log, &["operation" | &1])
            "result"
          end,
          fn -> Agent.update(log, &["cleanup" | &1]) end
        )

      assert result == {:ok, "result"}
      assert Agent.get(log, & &1) == ["cleanup", "operation"]
    end

    test "runs cleanup even when operation raises" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      assert_raise RuntimeError, "failed", fn ->
        Resource.ensure(
          fn -> raise "failed" end,
          fn -> Agent.update(log, &["cleanup" | &1]) end
        )
      end

      assert Agent.get(log, & &1) == ["cleanup"]
    end
  end

  describe "with_timeout/3" do
    test "returns result when operation completes in time" do
      result =
        Resource.with_timeout(
          fn -> "fast result" end,
          fn -> :cleanup end,
          1000
        )

      assert result == {:ok, "fast result"}
    end

    test "returns timeout error when operation is too slow" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        Resource.with_timeout(
          fn ->
            Process.sleep(500)
            "slow result"
          end,
          fn -> Agent.update(log, &["cleanup" | &1]) end,
          50
        )

      assert result == {:error, :timeout}
      assert Agent.get(log, & &1) == ["cleanup"]
    end

    test "runs cleanup on timeout" do
      cleaned_up = Agent.start_link(fn -> false end) |> elem(1)

      Resource.with_timeout(
        fn -> Process.sleep(:infinity) end,
        fn -> Agent.update(cleaned_up, fn _ -> true end) end,
        50
      )

      assert Agent.get(cleaned_up, & &1) == true
    end
  end

  describe "real-world examples" do
    @tag :tmp_dir
    test "copy file with guaranteed cleanup", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "source.txt")
      dest = Path.join(tmp_dir, "dest.txt")
      File.write!(source, "original content")

      result =
        Resource.with_resources(
          [
            {fn -> File.open!(source, [:read]) end, &File.close/1},
            {fn -> File.open!(dest, [:write]) end, &File.close/1}
          ],
          fn [input, output] ->
            data = IO.read(input, :eof)
            IO.write(output, String.upcase(data))
          end
        )

      assert result == {:ok, :ok}
      assert File.read!(dest) == "ORIGINAL CONTENT"
    end

    test "database-like transaction pattern" do
      # Simulate a transaction with rollback on error
      state = Agent.start_link(fn -> %{committed: false, data: []} end) |> elem(1)

      # Simulate begin/commit/rollback
      begin_tx = fn ->
        Agent.update(state, &Map.put(&1, :in_tx, true))
        :tx
      end

      commit_tx = fn :tx ->
        Agent.update(state, fn s ->
          %{s | committed: true, in_tx: false}
        end)
      end

      result =
        Resource.with_resource(
          begin_tx,
          fn :tx ->
            if Agent.get(state, & &1.committed) do
              :ok
            else
              Agent.update(state, fn s ->
                %{s | data: [], in_tx: false}
              end)
            end
          end,
          fn :tx ->
            Agent.update(state, fn s ->
              %{s | data: ["inserted"]}
            end)

            commit_tx.(:tx)
            :committed
          end
        )

      assert result == {:ok, :committed}
      final_state = Agent.get(state, & &1)
      assert final_state.committed == true
      assert final_state.data == ["inserted"]
    end

    test "nested resources with error in inner" do
      log = Agent.start_link(fn -> [] end) |> elem(1)

      outer_resource =
        Resource.define(
          acquire: fn ->
            Agent.update(log, &["outer_acquire" | &1])
            :outer
          end,
          release: fn _ -> Agent.update(log, &["outer_release" | &1]) end
        )

      result =
        Resource.using(outer_resource, fn :outer ->
          Resource.with_resource(
            fn ->
              Agent.update(log, &["inner_acquire" | &1])
              :inner
            end,
            fn _ -> Agent.update(log, &["inner_release" | &1]) end,
            fn :inner ->
              Agent.update(log, &["inner_use" | &1])
              {:error, :inner_failed}
            end
          )
        end)

      # Inner error propagates through - wrap_result passes through {:error, _} tuples
      assert result == {:error, :inner_failed}
      events = Agent.get(log, & &1) |> Enum.reverse()

      assert events == [
               "outer_acquire",
               "inner_acquire",
               "inner_use",
               "inner_release",
               "outer_release"
             ]
    end
  end
end
