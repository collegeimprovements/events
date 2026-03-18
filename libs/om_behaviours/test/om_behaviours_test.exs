defmodule OmBehavioursTest do
  use ExUnit.Case, async: true

  # --- Test support modules ---

  defmodule WithAdapter do
    @behaviour OmBehaviours.Adapter

    @impl true
    def adapter_name, do: :test

    @impl true
    def adapter_config(_opts), do: %{}
  end

  defmodule WithService do
    @behaviour OmBehaviours.Service

    @impl true
    def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

    @impl true
    def start_link(_opts), do: {:ok, self()}
  end

  defmodule WithBuilder do
    use OmBehaviours.Builder

    defstruct [:data]

    @impl true
    def new(data, _opts), do: %__MODULE__{data: data}

    @impl true
    def compose(builder, _op), do: builder

    @impl true
    def build(builder), do: builder.data
  end

  defmodule WithWorker do
    use OmBehaviours.Worker

    @impl true
    def perform(_args), do: {:ok, :done}
  end

  defmodule WithPlugin do
    use OmBehaviours.Plugin

    @impl true
    def plugin_name, do: :test

    @impl true
    def validate(_opts), do: :ok

    @impl true
    def prepare(opts), do: {:ok, opts}
  end

  defmodule WithHealthCheck do
    use OmBehaviours.HealthCheck

    @impl true
    def name, do: :test

    @impl true
    def severity, do: :info

    @impl true
    def check, do: {:ok, %{}}
  end

  defmodule WithMultipleBehaviours do
    @behaviour OmBehaviours.Adapter
    @behaviour OmBehaviours.Service

    @impl OmBehaviours.Adapter
    def adapter_name, do: :multi

    @impl OmBehaviours.Adapter
    def adapter_config(_opts), do: %{}

    @impl OmBehaviours.Service
    def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

    @impl OmBehaviours.Service
    def start_link(_opts), do: {:ok, self()}
  end

  defmodule PlainModule do
    def hello, do: :world
  end

  # --- Tests ---

  describe "implements?/2" do
    test "returns true when module implements the given behaviour" do
      assert OmBehaviours.implements?(WithAdapter, OmBehaviours.Adapter)
      assert OmBehaviours.implements?(WithService, OmBehaviours.Service)
      assert OmBehaviours.implements?(WithBuilder, OmBehaviours.Builder)
      assert OmBehaviours.implements?(WithWorker, OmBehaviours.Worker)
      assert OmBehaviours.implements?(WithPlugin, OmBehaviours.Plugin)
      assert OmBehaviours.implements?(WithHealthCheck, OmBehaviours.HealthCheck)
    end

    test "returns false when module does not implement the given behaviour" do
      refute OmBehaviours.implements?(WithAdapter, OmBehaviours.Service)
      refute OmBehaviours.implements?(WithService, OmBehaviours.Adapter)
      refute OmBehaviours.implements?(WithBuilder, OmBehaviours.Adapter)
      refute OmBehaviours.implements?(WithWorker, OmBehaviours.Adapter)
      refute OmBehaviours.implements?(WithPlugin, OmBehaviours.Service)
      refute OmBehaviours.implements?(WithHealthCheck, OmBehaviours.Worker)
    end

    test "returns false for a plain module with no behaviours" do
      refute OmBehaviours.implements?(PlainModule, OmBehaviours.Adapter)
      refute OmBehaviours.implements?(PlainModule, OmBehaviours.Service)
      refute OmBehaviours.implements?(PlainModule, OmBehaviours.Builder)
    end

    test "returns false for a non-existent module" do
      refute OmBehaviours.implements?(DoesNotExist.At.All, OmBehaviours.Adapter)
    end

    test "returns false for non-atom inputs" do
      refute OmBehaviours.implements?("not_a_module", OmBehaviours.Adapter)
      refute OmBehaviours.implements?(123, OmBehaviours.Adapter)
      refute OmBehaviours.implements?(WithAdapter, "not_a_behaviour")
    end

    test "handles module with multiple behaviours" do
      assert OmBehaviours.implements?(WithMultipleBehaviours, OmBehaviours.Adapter)
      assert OmBehaviours.implements?(WithMultipleBehaviours, OmBehaviours.Service)
      refute OmBehaviours.implements?(WithMultipleBehaviours, OmBehaviours.Builder)
    end

    test "works with Elixir behaviours" do
      # GenServer defines callbacks but doesn't declare @behaviour on itself
      refute OmBehaviours.implements?(GenServer, GenServer)
    end
  end
end
