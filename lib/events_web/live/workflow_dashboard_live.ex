defmodule EventsWeb.WorkflowDashboardLive do
  @moduledoc """
  LiveView dashboard for monitoring workflow executions.

  Provides real-time visibility into:
  - Registered workflows
  - Running executions
  - Execution details and step progress
  - Statistics and metrics
  """

  use EventsWeb, :live_view

  alias OmScheduler.Workflow
  alias OmScheduler.Workflow.{Registry, Store}

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to workflow telemetry updates
      Phoenix.PubSub.subscribe(Events.Infra.PubSub.Server, "workflow:events")

      # Periodic refresh
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    {:ok,
     socket
     |> assign(:page_title, "Workflow Dashboard")
     |> assign(:view, :overview)
     |> assign(:selected_workflow, nil)
     |> assign(:selected_execution, nil)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:view, :overview)
    |> assign(:selected_workflow, nil)
    |> assign(:selected_execution, nil)
  end

  defp apply_action(socket, :workflow, %{"name" => name}) do
    workflow_name = String.to_existing_atom(name)

    socket
    |> assign(:view, :workflow)
    |> assign(:selected_workflow, workflow_name)
    |> load_workflow_executions(workflow_name)
  rescue
    ArgumentError ->
      socket
      |> put_flash(:error, "Workflow not found: #{name}")
      |> push_navigate(to: ~p"/workflows")
  end

  defp apply_action(socket, :execution, %{"id" => id}) do
    case get_execution(id) do
      {:ok, execution} ->
        socket
        |> assign(:view, :execution)
        |> assign(:selected_execution, execution)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Execution not found: #{id}")
        |> push_navigate(to: ~p"/workflows")
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  def handle_info({:workflow_event, _event, _data}, socket) do
    # Real-time update from telemetry
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("cancel_execution", %{"id" => id}, socket) do
    case Workflow.cancel(id, reason: :user_requested) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Execution cancelled")
         |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel: #{inspect(reason)}")}
    end
  end

  def handle_event("pause_execution", %{"id" => id}, socket) do
    case Workflow.pause(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Execution paused")
         |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
    end
  end

  def handle_event("resume_execution", %{"id" => id}, socket) do
    case Workflow.resume(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Execution resumed")
         |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
    end
  end

  def handle_event("start_workflow", %{"name" => name}, socket) do
    workflow_name = String.to_existing_atom(name)

    case Workflow.start(workflow_name, %{}) do
      {:ok, exec_id} ->
        {:noreply,
         socket
         |> put_flash(:info, "Started execution: #{exec_id}")
         |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  rescue
    _ ->
      {:noreply, put_flash(socket, :error, "Invalid workflow name")}
  end

  # ============================================
  # Data Loading
  # ============================================

  defp load_data(socket) do
    socket
    |> assign(:workflows, get_workflows())
    |> assign(:running_executions, get_running_executions())
    |> assign(:stats, get_stats())
  end

  defp load_workflow_executions(socket, workflow_name) do
    executions = get_workflow_executions(workflow_name)
    assign(socket, :workflow_executions, executions)
  end

  defp get_workflows do
    try do
      Registry.list_workflows()
    catch
      :exit, _ -> []
    end
  end

  defp get_running_executions do
    try do
      Registry.list_running_executions(limit: 50)
    catch
      :exit, _ ->
        case Store.list_running_executions(limit: 50) do
          {:ok, execs} -> execs
          _ -> []
        end
    end
  end

  defp get_workflow_executions(workflow_name) do
    case Store.list_executions(workflow_name, limit: 20) do
      {:ok, execs} -> execs
      _ -> []
    end
  end

  defp get_execution(id) do
    # Try Registry first
    try do
      case Registry.get_execution(id) do
        {:ok, exec} -> {:ok, exec}
        {:error, :not_found} -> Store.get_execution(id)
      end
    catch
      :exit, _ -> Store.get_execution(id)
    end
  end

  defp get_stats do
    try do
      Registry.get_stats()
    catch
      :exit, _ ->
        Store.get_stats()
    end
  end

  # ============================================
  # Render
  # ============================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Workflow Dashboard</h1>
        <div class="flex gap-2">
          <.link
            navigate={~p"/workflows"}
            class="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-700 hover:text-gray-900 hover:bg-gray-100 rounded-md transition-colors"
          >
            Overview
          </.link>
        </div>
      </div>

      <%= case @view do %>
        <% :overview -> %>
          <.overview_view
            workflows={@workflows}
            running_executions={@running_executions}
            stats={@stats}
          />
        <% :workflow -> %>
          <.workflow_view
            workflow_name={@selected_workflow}
            executions={@workflow_executions || []}
          />
        <% :execution -> %>
          <.execution_view execution={@selected_execution} />
      <% end %>
    </div>
    """
  end

  # ============================================
  # Components
  # ============================================

  defp overview_view(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
      <.stat_card title="Workflows" value={@stats[:workflows] || 0} icon="hero-rectangle-stack" />
      <.stat_card
        title="Running"
        value={@stats[:executions][:by_state][:running] || 0}
        icon="hero-play"
        color="green"
      />
      <.stat_card
        title="Total Executions"
        value={@stats[:executions][:total] || 0}
        icon="hero-chart-bar"
      />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
      <div class="bg-white rounded-lg shadow-md border border-gray-200">
        <div class="p-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Registered Workflows</h2>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead>
                <tr class="bg-gray-50">
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Steps
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Trigger
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for workflow <- @workflows do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-4 py-3 whitespace-nowrap">
                      <.link
                        navigate={~p"/workflows/#{workflow.name}"}
                        class="text-blue-600 hover:text-blue-800 font-medium"
                      >
                        {workflow.name}
                      </.link>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                      {map_size(workflow.steps)}
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <.trigger_badge type={workflow.trigger_type} />
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <button
                        phx-click="start_workflow"
                        phx-value-name={workflow.name}
                        class="inline-flex items-center px-2.5 py-1.5 text-xs font-medium text-white bg-blue-600 hover:bg-blue-700 rounded transition-colors"
                      >
                        Start
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow-md border border-gray-200">
        <div class="p-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Running Executions</h2>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead>
                <tr class="bg-gray-50">
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Workflow
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    State
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Started
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for exec <- @running_executions do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-4 py-3 whitespace-nowrap">
                      <.link
                        navigate={~p"/workflows/executions/#{exec.id}"}
                        class="text-blue-600 hover:text-blue-800"
                      >
                        {exec.workflow_name}
                      </.link>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <.state_badge state={exec.state} />
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                      {format_time(exec.started_at)}
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <div class="flex gap-1">
                        <%= if exec.state == :running do %>
                          <button
                            phx-click="pause_execution"
                            phx-value-id={exec.id}
                            class="inline-flex items-center px-2 py-1 text-xs font-medium text-yellow-700 bg-yellow-100 hover:bg-yellow-200 rounded transition-colors"
                          >
                            Pause
                          </button>
                        <% end %>
                        <%= if exec.state == :paused do %>
                          <button
                            phx-click="resume_execution"
                            phx-value-id={exec.id}
                            class="inline-flex items-center px-2 py-1 text-xs font-medium text-green-700 bg-green-100 hover:bg-green-200 rounded transition-colors"
                          >
                            Resume
                          </button>
                        <% end %>
                        <button
                          phx-click="cancel_execution"
                          phx-value-id={exec.id}
                          class="inline-flex items-center px-2 py-1 text-xs font-medium text-red-700 bg-red-100 hover:bg-red-200 rounded transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp workflow_view(assigns) do
    ~H"""
    <div class="mb-4">
      <.link navigate={~p"/workflows"} class="text-blue-600 hover:text-blue-800">
        &larr; Back to Overview
      </.link>
    </div>

    <div class="bg-white rounded-lg shadow-md border border-gray-200 mb-8">
      <div class="p-6">
        <div class="flex justify-between items-center">
          <h2 class="text-2xl font-semibold text-gray-900">{@workflow_name}</h2>
          <button
            phx-click="start_workflow"
            phx-value-name={@workflow_name}
            class="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-md transition-colors"
          >
            Start New Execution
          </button>
        </div>
      </div>
    </div>

    <div class="bg-white rounded-lg shadow-md border border-gray-200">
      <div class="p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Executions</h3>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead>
              <tr class="bg-gray-50">
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  ID
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  State
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Progress
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Started
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Duration
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for exec <- @executions do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-4 py-3 whitespace-nowrap">
                    <.link
                      navigate={~p"/workflows/executions/#{exec.id}"}
                      class="text-blue-600 hover:text-blue-800 font-mono text-sm"
                    >
                      {String.slice(exec.id, 0..7)}...
                    </.link>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <.state_badge state={exec.state} />
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <.progress_bar
                      completed={length(exec.completed_steps)}
                      total={
                        length(exec.completed_steps) + length(exec.pending_steps) +
                          length(exec.running_steps)
                      }
                    />
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                    {format_time(exec.started_at)}
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                    {format_duration(exec.duration_ms)}
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <.link
                      navigate={~p"/workflows/executions/#{exec.id}"}
                      class="text-gray-600 hover:text-gray-900 text-sm"
                    >
                      View
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp execution_view(assigns) do
    ~H"""
    <div class="mb-4">
      <.link
        navigate={~p"/workflows/#{@execution.workflow_name}"}
        class="text-blue-600 hover:text-blue-800"
      >
        &larr; Back to {@execution.workflow_name}
      </.link>
    </div>

    <div class="bg-white rounded-lg shadow-md border border-gray-200 mb-8">
      <div class="p-6">
        <div class="flex justify-between items-center">
          <div>
            <h2 class="text-2xl font-semibold text-gray-900">{@execution.workflow_name}</h2>
            <p class="text-sm text-gray-500 font-mono">{@execution.id}</p>
          </div>
          <.state_badge state={@execution.state} size="lg" />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6">
          <div>
            <p class="text-sm text-gray-500">Started</p>
            <p class="font-medium text-gray-900">{format_time(@execution.started_at)}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Duration</p>
            <p class="font-medium text-gray-900">{format_duration(@execution.duration_ms)}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Trigger</p>
            <p class="font-medium text-gray-900">{@execution.trigger.type}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Attempt</p>
            <p class="font-medium text-gray-900">{@execution.attempt}</p>
          </div>
        </div>

        <div class="flex gap-2 mt-6">
          <%= if @execution.state == :running do %>
            <button
              phx-click="pause_execution"
              phx-value-id={@execution.id}
              class="inline-flex items-center px-4 py-2 text-sm font-medium text-yellow-700 bg-yellow-100 hover:bg-yellow-200 rounded-md transition-colors"
            >
              Pause
            </button>
          <% end %>
          <%= if @execution.state == :paused do %>
            <button
              phx-click="resume_execution"
              phx-value-id={@execution.id}
              class="inline-flex items-center px-4 py-2 text-sm font-medium text-green-700 bg-green-100 hover:bg-green-200 rounded-md transition-colors"
            >
              Resume
            </button>
          <% end %>
          <%= if @execution.state in [:running, :paused] do %>
            <button
              phx-click="cancel_execution"
              phx-value-id={@execution.id}
              class="inline-flex items-center px-4 py-2 text-sm font-medium text-red-700 bg-red-100 hover:bg-red-200 rounded-md transition-colors"
            >
              Cancel
            </button>
          <% end %>
        </div>
      </div>
    </div>

    <div class="bg-white rounded-lg shadow-md border border-gray-200 mb-8">
      <div class="p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Steps</h3>
        <.step_timeline execution={@execution} />
      </div>
    </div>

    <%= if @execution.error do %>
      <div class="bg-red-50 rounded-lg border border-red-200 mb-8">
        <div class="p-6">
          <h3 class="text-lg font-semibold text-red-800 mb-2">Error</h3>
          <pre class="bg-red-100 p-4 rounded overflow-auto text-sm text-red-900"><%= inspect(@execution.error, pretty: true) %></pre>
          <%= if @execution.stacktrace do %>
            <details class="mt-4">
              <summary class="cursor-pointer text-sm text-red-600 hover:text-red-800">
                Stacktrace
              </summary>
              <pre class="bg-red-100 p-4 rounded overflow-auto text-xs mt-2 text-red-900"><%= @execution.stacktrace %></pre>
            </details>
          <% end %>
        </div>
      </div>
    <% end %>

    <div class="bg-white rounded-lg shadow-md border border-gray-200">
      <div class="p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Context</h3>
        <pre class="bg-gray-100 p-4 rounded overflow-auto text-sm text-gray-800"><%= inspect(@execution.context, pretty: true, limit: :infinity) %></pre>
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    assigns = assign_new(assigns, :color, fn -> "blue" end)

    color_classes =
      case assigns.color do
        "green" -> "text-green-600"
        "red" -> "text-red-600"
        "yellow" -> "text-yellow-600"
        _ -> "text-blue-600"
      end

    assigns = assign(assigns, :color_classes, color_classes)

    ~H"""
    <div class="bg-white rounded-lg shadow-md border border-gray-200 p-6">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-medium text-gray-500">{@title}</p>
          <p class={"text-3xl font-bold #{@color_classes}"}>{@value}</p>
        </div>
        <div class={@color_classes}>
          <.icon name={@icon} class="size-10 opacity-75" />
        </div>
      </div>
    </div>
    """
  end

  defp trigger_badge(assigns) do
    {bg_class, text_class} =
      case assigns.type do
        :manual -> {"bg-gray-100", "text-gray-700"}
        :scheduled -> {"bg-blue-100", "text-blue-700"}
        :event -> {"bg-yellow-100", "text-yellow-700"}
        _ -> {"bg-gray-100", "text-gray-700"}
      end

    assigns = assign(assigns, bg_class: bg_class, text_class: text_class)

    ~H"""
    <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{@bg_class} #{@text_class}"}>
      {@type}
    </span>
    """
  end

  defp state_badge(assigns) do
    assigns = assign_new(assigns, :size, fn -> "md" end)

    {bg_class, text_class, text} =
      case assigns.state do
        :pending -> {"bg-gray-100", "text-gray-700", "Pending"}
        :running -> {"bg-blue-100", "text-blue-700", "Running"}
        :completed -> {"bg-green-100", "text-green-700", "Completed"}
        :failed -> {"bg-red-100", "text-red-700", "Failed"}
        :cancelled -> {"bg-yellow-100", "text-yellow-700", "Cancelled"}
        :paused -> {"bg-yellow-100", "text-yellow-700", "Paused"}
        _ -> {"bg-gray-100", "text-gray-700", to_string(assigns.state)}
      end

    size_class = if assigns.size == "lg", do: "px-3 py-1 text-sm", else: "px-2 py-0.5 text-xs"

    assigns =
      assign(assigns,
        bg_class: bg_class,
        text_class: text_class,
        text: text,
        size_class: size_class
      )

    ~H"""
    <span class={"inline-flex items-center rounded font-medium #{@bg_class} #{@text_class} #{@size_class}"}>
      {@text}
    </span>
    """
  end

  defp progress_bar(assigns) do
    pct = if assigns.total > 0, do: round(assigns.completed / assigns.total * 100), else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="flex items-center gap-2">
      <div class="w-20 h-2 bg-gray-200 rounded-full overflow-hidden">
        <div class="h-full bg-blue-600 rounded-full transition-all" style={"width: #{@pct}%"}></div>
      </div>
      <span class="text-sm text-gray-500">{@completed}/{@total}</span>
    </div>
    """
  end

  defp step_timeline(assigns) do
    steps = build_step_list(assigns.execution)
    assigns = assign(assigns, :steps, steps)

    ~H"""
    <div class="relative">
      <%= for {step, idx} <- Enum.with_index(@steps) do %>
        <div class="flex items-start mb-4 last:mb-0">
          <div class="flex flex-col items-center mr-4">
            <div class={"w-8 h-8 rounded-full flex items-center justify-center #{step_bg_class(step.state)}"}>
              <.step_icon state={step.state} />
            </div>
            <%= if idx < length(@steps) - 1 do %>
              <div class={"w-0.5 h-8 mt-1 #{step_line_class(step.state)}"}></div>
            <% end %>
          </div>
          <div class="flex-1 min-w-0 pt-1">
            <div class="flex items-center gap-2">
              <span class="font-medium text-gray-900">{step.name}</span>
              <span class="text-xs text-gray-500">{format_step_time(step)}</span>
            </div>
            <%= if step.error do %>
              <p class="text-sm text-red-600 mt-1">{inspect(step.error)}</p>
            <% end %>
            <%= if step.result && step.state == :completed do %>
              <p class="text-sm text-gray-500 mt-1 truncate">
                {inspect(step.result, limit: 3)}
              </p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp step_icon(assigns) do
    {icon, color_class} =
      case assigns.state do
        :completed -> {"hero-check-circle", "text-green-600"}
        :running -> {"hero-arrow-path", "text-blue-600 animate-spin"}
        :failed -> {"hero-x-circle", "text-red-600"}
        :skipped -> {"hero-minus-circle", "text-gray-400"}
        :cancelled -> {"hero-stop-circle", "text-yellow-600"}
        _ -> {"hero-clock", "text-gray-400"}
      end

    assigns = assign(assigns, icon: icon, color_class: color_class)

    ~H"""
    <.icon name={@icon} class={"size-5 #{@color_class}"} />
    """
  end

  defp step_bg_class(state) do
    case state do
      :completed -> "bg-green-100"
      :running -> "bg-blue-100"
      :failed -> "bg-red-100"
      :cancelled -> "bg-yellow-100"
      _ -> "bg-gray-100"
    end
  end

  defp step_line_class(state) do
    case state do
      :completed -> "bg-green-300"
      :running -> "bg-blue-300"
      :failed -> "bg-red-300"
      _ -> "bg-gray-200"
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp build_step_list(execution) do
    all_steps =
      MapSet.new(
        execution.completed_steps ++
          execution.running_steps ++
          execution.pending_steps ++
          execution.skipped_steps ++
          execution.cancelled_steps
      )

    Enum.map(all_steps, fn step_name ->
      state =
        cond do
          step_name in execution.completed_steps -> :completed
          step_name in execution.running_steps -> :running
          step_name in execution.skipped_steps -> :skipped
          step_name in execution.cancelled_steps -> :cancelled
          true -> :pending
        end

      %{
        name: step_name,
        state: state,
        result: Map.get(execution.step_results, step_name),
        error: Map.get(execution.step_errors, step_name),
        attempt: Map.get(execution.step_attempts, step_name, 0)
      }
    end)
    |> Enum.sort_by(fn step ->
      case step.state do
        :completed -> 0
        :running -> 1
        :pending -> 2
        :skipped -> 3
        :cancelled -> 4
        _ -> 5
      end
    end)
  end

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_time(_), do: "-"

  defp format_step_time(%{state: :completed}), do: "done"
  defp format_step_time(%{state: :running}), do: "running"
  defp format_step_time(_), do: ""

  defp format_duration(nil), do: "-"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"
end
