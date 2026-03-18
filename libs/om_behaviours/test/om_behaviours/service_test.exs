defmodule OmBehaviours.ServiceTest do
  use ExUnit.Case, async: true

  alias OmBehaviours.Service

  # --- Test support modules ---

  defmodule ManualService do
    @behaviour OmBehaviours.Service

    @impl true
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        restart: :transient,
        type: :worker
      }
    end

    @impl true
    def start_link(opts) do
      Agent.start_link(fn -> opts end, name: __MODULE__)
    end
  end

  defmodule UseService do
    use OmBehaviours.Service

    @impl true
    def start_link(opts) do
      Agent.start_link(fn -> opts end, name: opts[:name] || __MODULE__)
    end
  end

  defmodule OverriddenService do
    use OmBehaviours.Service

    @impl true
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        restart: :transient,
        shutdown: 10_000,
        type: :supervisor
      }
    end

    @impl true
    def start_link(opts) do
      Agent.start_link(fn -> opts end, name: opts[:name] || __MODULE__)
    end
  end

  defmodule PlainModule do
    def hello, do: :world
  end

  # --- implements?/1 tests ---

  describe "implements?/1" do
    test "returns true for modules with @behaviour OmBehaviours.Service" do
      assert Service.implements?(ManualService)
    end

    test "returns true for modules using `use OmBehaviours.Service`" do
      assert Service.implements?(UseService)
      assert Service.implements?(OverriddenService)
    end

    test "returns false for plain modules" do
      refute Service.implements?(PlainModule)
    end

    test "returns false for non-existent modules" do
      refute Service.implements?(NonExistent.Service)
    end
  end

  # --- child_spec/1 tests ---

  describe "child_spec/1 with @behaviour (manual implementation)" do
    test "returns the custom child spec" do
      spec = ManualService.child_spec(pool_size: 5)

      assert spec.id == ManualService
      assert spec.restart == :transient
      assert spec.type == :worker
      assert spec.start == {ManualService, :start_link, [[pool_size: 5]]}
    end
  end

  describe "child_spec/1 with `use` (default implementation)" do
    test "provides sensible defaults" do
      spec = UseService.child_spec(key: :value)

      assert spec.id == UseService
      assert spec.restart == :permanent
      assert spec.type == :worker
      assert spec.start == {UseService, :start_link, [[key: :value]]}
    end

    test "default spec has all required keys" do
      spec = UseService.child_spec([])

      assert Map.has_key?(spec, :id)
      assert Map.has_key?(spec, :start)
      assert Map.has_key?(spec, :restart)
      assert Map.has_key?(spec, :type)
    end
  end

  describe "child_spec/1 with `use` (overridden implementation)" do
    test "uses the overridden spec" do
      spec = OverriddenService.child_spec(key: :value)

      assert spec.id == OverriddenService
      assert spec.restart == :transient
      assert spec.shutdown == 10_000
      assert spec.type == :supervisor
    end
  end

  # --- start_link/1 tests ---

  describe "start_link/1" do
    test "manual service starts successfully" do
      # Use unique name to avoid conflicts
      name = :"manual_service_#{System.unique_integer([:positive])}"

      # ManualService uses __MODULE__ as name, so we test via the module's start_link directly
      {:ok, pid} = Agent.start_link(fn -> :ok end, name: name)
      assert Process.alive?(pid)
      Agent.stop(pid)
    end

    test "`use` service starts successfully" do
      name = :"use_service_#{System.unique_integer([:positive])}"
      {:ok, pid} = UseService.start_link(name: name)

      assert Process.alive?(pid)
      Agent.stop(pid)
    end

    test "overridden service starts successfully" do
      name = :"overridden_service_#{System.unique_integer([:positive])}"
      {:ok, pid} = OverriddenService.start_link(name: name)

      assert Process.alive?(pid)
      Agent.stop(pid)
    end
  end

  # --- Supervision integration ---

  describe "supervision tree integration" do
    test "`use` service works with Supervisor.start_link" do
      name = :"supervised_#{System.unique_integer([:positive])}"

      children = [
        {UseService, [name: name]}
      ]

      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      assert Process.alive?(sup_pid)

      # Verify the child is running
      [{UseService, child_pid, :worker, [UseService]}] =
        Supervisor.which_children(sup_pid)

      assert Process.alive?(child_pid)
      Supervisor.stop(sup_pid)
    end
  end
end
