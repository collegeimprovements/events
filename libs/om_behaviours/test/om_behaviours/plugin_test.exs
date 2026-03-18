defmodule OmBehaviours.PluginTest do
  use ExUnit.Case, async: true

  alias OmBehaviours.Plugin

  # --- Test support modules ---

  defmodule StatelessPlugin do
    use OmBehaviours.Plugin

    @impl true
    def plugin_name, do: :stateless

    @impl true
    def validate(opts) do
      case Keyword.fetch(opts, :key) do
        {:ok, _} -> :ok
        :error -> {:error, ":key is required"}
      end
    end

    @impl true
    def prepare(opts) do
      {:ok, %{key: Keyword.fetch!(opts, :key)}}
    end
  end

  defmodule StatefulPlugin do
    use OmBehaviours.Plugin

    @impl true
    def plugin_name, do: :stateful

    @impl true
    def validate(_opts), do: :ok

    @impl true
    def prepare(opts) do
      {:ok, %{interval: Keyword.get(opts, :interval, 5_000)}}
    end

    @impl true
    def start_link(state) do
      Agent.start_link(fn -> state end, name: __MODULE__)
    end
  end

  defmodule FailingPlugin do
    use OmBehaviours.Plugin

    @impl true
    def plugin_name, do: :failing

    @impl true
    def validate(_opts), do: {:error, "always fails"}

    @impl true
    def prepare(_opts), do: {:error, "cannot prepare"}
  end

  defmodule ManualPlugin do
    @behaviour OmBehaviours.Plugin

    @impl true
    def plugin_name, do: :manual

    @impl true
    def validate(_opts), do: :ok

    @impl true
    def prepare(opts), do: {:ok, opts}

    @impl true
    def start_link(_state), do: {:ok, self()}
  end

  defmodule PlainModule do
    def hello, do: :world
  end

  # --- implements?/1 tests ---

  describe "implements?/1" do
    test "returns true for modules using Plugin" do
      assert Plugin.implements?(StatelessPlugin)
      assert Plugin.implements?(StatefulPlugin)
      assert Plugin.implements?(FailingPlugin)
    end

    test "returns true for modules with @behaviour directly" do
      assert Plugin.implements?(ManualPlugin)
    end

    test "returns false for plain modules" do
      refute Plugin.implements?(PlainModule)
    end

    test "returns false for non-existent modules" do
      refute Plugin.implements?(NonExistent.Plugin)
    end
  end

  # --- plugin_name/0 tests ---

  describe "plugin_name/0" do
    test "returns the configured atom name" do
      assert StatelessPlugin.plugin_name() == :stateless
      assert StatefulPlugin.plugin_name() == :stateful
      assert FailingPlugin.plugin_name() == :failing
      assert ManualPlugin.plugin_name() == :manual
    end
  end

  # --- validate/1 tests ---

  describe "validate/1" do
    test "returns :ok with valid configuration" do
      assert :ok = StatelessPlugin.validate(key: "my-key")
    end

    test "returns {:error, reason} with invalid configuration" do
      assert {:error, ":key is required"} = StatelessPlugin.validate([])
    end

    test "always-failing plugin returns error" do
      assert {:error, "always fails"} = FailingPlugin.validate(anything: true)
    end

    test "permissive plugin accepts any config" do
      assert :ok = StatefulPlugin.validate([])
      assert :ok = ManualPlugin.validate(random: :stuff)
    end
  end

  # --- prepare/1 tests ---

  describe "prepare/1" do
    test "returns {:ok, state} with valid opts" do
      assert {:ok, %{key: "secret"}} = StatelessPlugin.prepare(key: "secret")
    end

    test "applies defaults in prepare" do
      assert {:ok, %{interval: 5_000}} = StatefulPlugin.prepare([])
    end

    test "overrides defaults with provided values" do
      assert {:ok, %{interval: 10_000}} = StatefulPlugin.prepare(interval: 10_000)
    end

    test "returns {:error, reason} on failure" do
      assert {:error, "cannot prepare"} = FailingPlugin.prepare([])
    end

    test "manual plugin passes opts through" do
      opts = [a: 1, b: 2]
      assert {:ok, ^opts} = ManualPlugin.prepare(opts)
    end
  end

  # --- start_link/1 tests ---

  describe "start_link/1" do
    test "default returns :ignore for stateless plugins" do
      assert :ignore = StatelessPlugin.start_link(%{key: "test"})
    end

    test "stateful plugin starts a process" do
      {:ok, pid} = StatefulPlugin.start_link(%{interval: 1_000})
      assert Process.alive?(pid)
      Agent.stop(pid)
    end

    test "manual plugin returns {:ok, pid}" do
      assert {:ok, pid} = ManualPlugin.start_link(%{})
      assert is_pid(pid)
    end
  end

  # --- __using__ macro ---

  describe "__using__ macro" do
    test "injects @behaviour OmBehaviours.Plugin" do
      behaviours =
        StatelessPlugin.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert OmBehaviours.Plugin in behaviours
    end

    test "provides default start_link that returns :ignore" do
      assert :ignore = StatelessPlugin.start_link(%{})
    end

    test "start_link is overridable" do
      # StatefulPlugin overrides start_link
      {:ok, pid} = StatefulPlugin.start_link(%{})
      assert Process.alive?(pid)
      Agent.stop(pid)
    end
  end

  # --- Lifecycle integration ---

  describe "plugin lifecycle" do
    test "validate → prepare → start_link (stateless)" do
      opts = [key: "my-api-key"]

      assert :ok = StatelessPlugin.validate(opts)
      assert {:ok, state} = StatelessPlugin.prepare(opts)
      assert state == %{key: "my-api-key"}
      assert :ignore = StatelessPlugin.start_link(state)
    end

    test "validate → prepare → start_link (stateful)" do
      opts = [interval: 3_000]

      assert :ok = StatefulPlugin.validate(opts)
      assert {:ok, state} = StatefulPlugin.prepare(opts)
      assert state == %{interval: 3_000}

      {:ok, pid} = StatefulPlugin.start_link(state)
      assert Process.alive?(pid)
      assert Agent.get(pid, & &1) == %{interval: 3_000}
      Agent.stop(pid)
    end

    test "validation failure short-circuits lifecycle" do
      assert {:error, _} = FailingPlugin.validate([])
      # Would not proceed to prepare/start_link in real usage
    end
  end
end
