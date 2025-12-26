defmodule OmScheduler.Queue.Supervisor do
  @moduledoc """
  Supervises queue producers.

  Starts a producer for each configured queue with its concurrency limit.
  """

  use Supervisor
  require Logger

  alias OmScheduler.Queue.Producer
  alias OmScheduler.Config

  # ============================================
  # Client API
  # ============================================

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end

  @doc """
  Gets the producer process for a queue.
  """
  @spec get_producer(atom(), atom()) :: pid() | nil
  def get_producer(_supervisor \\ __MODULE__, queue) do
    producer_name = producer_name(queue)

    case Process.whereis(producer_name) do
      nil -> nil
      pid -> pid
    end
  end

  @doc """
  Returns stats for all queues.
  """
  @spec all_stats(atom()) :: map()
  def all_stats(supervisor \\ __MODULE__) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      if is_pid(pid) do
        try do
          GenServer.call(pid, :stats, 1000)
        catch
          _, _ -> nil
        end
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn stats -> {stats.queue, stats} end)
  end

  # ============================================
  # Supervisor Callbacks
  # ============================================

  @impl Supervisor
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())
    queues = conf[:queues] || [default: 10]
    store = Keyword.get(opts, :store)

    children =
      if queues == false do
        []
      else
        Enum.map(queues, fn {queue, concurrency} ->
          producer_opts = [
            name: producer_name(queue),
            queue: queue,
            concurrency: concurrency,
            store: store,
            conf: conf
          ]

          {Producer, producer_opts}
        end)
      end

    Logger.debug("[Scheduler.Queue.Supervisor] Starting #{length(children)} queue producers")

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp producer_name(queue) do
    :"OmScheduler.Queue.Producer.#{queue}"
  end
end
