defmodule Events.Types.Debouncer do
  @moduledoc """
  Debounce mechanism - only executes after a quiet period.

  Debouncing delays execution until a specified time has passed without
  any new calls. Useful for search-as-you-type, auto-save, resize handlers,
  or any situation where you want to wait for user activity to stop.

  ## Usage

      # Start a debouncer (add to supervision tree for long-lived use)
      {:ok, debouncer} = Debouncer.start_link()

      # Debounce calls - only the last one executes
      Debouncer.call(debouncer, fn -> search(query1) end, 200)
      Debouncer.call(debouncer, fn -> search(query2) end, 200)
      Debouncer.call(debouncer, fn -> search(query3) end, 200)
      # Only search(query3) runs, 200ms after the last call

      # Cancel pending execution
      Debouncer.cancel(debouncer)

  ## Supervision

      children = [
        {Events.Types.Debouncer, name: :search_debouncer}
      ]

  ## Difference from Throttle

  - **Debounce**: Waits for quiet period, then executes once
  - **Throttle**: Executes immediately, blocks subsequent calls for interval

  Use debounce when you want to wait for activity to stop.
  Use throttle when you want regular execution at a maximum rate.
  """

  use GenServer

  @type t :: pid() | atom()

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts a debouncer process.

  ## Options

    * `:name` - Optional name for the process (atom)

  ## Examples

      {:ok, debouncer} = Debouncer.start_link()
      {:ok, debouncer} = Debouncer.start_link(name: :my_debouncer)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @doc """
  Debounces a function call.

  If called again before `delay` milliseconds, the previous call is cancelled
  and the timer resets. The function only executes after `delay` ms of quiet.

  This is a blocking call that returns when the function executes.

  ## Parameters

    * `debouncer` - The debouncer pid or name
    * `fun` - Zero-arity function to execute
    * `delay` - Milliseconds to wait for quiet (default: 100)

  ## Examples

      # Execute search after 200ms of no typing
      Debouncer.call(debouncer, fn -> search(query) end, 200)
  """
  @spec call(t(), (-> result), non_neg_integer()) :: result when result: term()
  def call(debouncer, fun, delay \\ 100) when is_function(fun, 0) do
    GenServer.call(debouncer, {:debounce, fun, delay}, :infinity)
  end

  @doc """
  Cancels any pending debounced call.

  Returns `:ok` if a pending call was cancelled, `:noop` if nothing was pending.

  ## Examples

      Debouncer.call(debouncer, fn -> save() end, 1000)
      Debouncer.cancel(debouncer)  # Cancels the pending save
  """
  @spec cancel(t()) :: :ok | :noop
  def cancel(debouncer) do
    GenServer.call(debouncer, :cancel)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    {:ok, %{timer: nil, pending: nil, caller: nil}}
  end

  @impl true
  def handle_call({:debounce, fun, delay}, from, state) do
    # Cancel existing timer if any
    if state.timer, do: Process.cancel_timer(state.timer)

    # Reply to previous caller with :cancelled if there was one
    if state.caller do
      GenServer.reply(state.caller, {:error, :cancelled})
    end

    # Set new timer
    timer = Process.send_after(self(), :execute, delay)
    {:noreply, %{timer: timer, pending: fun, caller: from}}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    if state.timer do
      Process.cancel_timer(state.timer)

      if state.caller do
        GenServer.reply(state.caller, {:error, :cancelled})
      end

      {:reply, :ok, %{timer: nil, pending: nil, caller: nil}}
    else
      {:reply, :noop, state}
    end
  end

  @impl true
  def handle_info(:execute, %{pending: fun, caller: caller} = _state) when not is_nil(fun) do
    result = fun.()
    GenServer.reply(caller, result)
    {:noreply, %{timer: nil, pending: nil, caller: nil}}
  end

  @impl true
  def handle_info(:execute, state) do
    {:noreply, state}
  end
end
