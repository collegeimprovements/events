defmodule EventsWeb.TtydLive do
  @moduledoc """
  LiveView for web-based terminal sessions.

  Each browser tab that mounts this LiveView gets its own ttyd process.
  The terminal is embedded via iframe pointing to the ttyd server.

  ## Features

  - Per-tab terminal isolation
  - Automatic cleanup on tab close
  - Session management via SessionManager
  - Configurable shell command

  ## Usage

  Access at `/ttyd` - each tab gets a unique terminal session.

  """

  use EventsWeb, :live_view

  alias Events.Services.Ttyd.SessionManager

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      case start_terminal_session() do
        {:ok, session_id, port} ->
          {:ok,
           socket
           |> assign(:page_title, "Terminal")
           |> assign(:session_id, session_id)
           |> assign(:port, port)
           |> assign(:status, :ready)
           |> assign(:error, nil)}

        {:error, :no_ports_available} ->
          {:ok,
           socket
           |> assign(:page_title, "Terminal")
           |> assign(:session_id, nil)
           |> assign(:port, nil)
           |> assign(:status, :error)
           |> assign(:error, "No terminal slots available. Please try again later.")}

        {:error, reason} ->
          Logger.error("[TtydLive] Failed to start session: #{inspect(reason)}")

          {:ok,
           socket
           |> assign(:page_title, "Terminal")
           |> assign(:session_id, nil)
           |> assign(:port, nil)
           |> assign(:status, :error)
           |> assign(:error, "Failed to start terminal: #{inspect(reason)}")}
      end
    else
      # Initial static render before WebSocket connects
      {:ok,
       socket
       |> assign(:page_title, "Terminal")
       |> assign(:session_id, nil)
       |> assign(:port, nil)
       |> assign(:status, :connecting)
       |> assign(:error, nil)}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:session_id] do
      SessionManager.stop_session(socket.assigns.session_id)
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="ttyd-container" style="height: 100vh; display: flex; flex-direction: column;">
      <div class="ttyd-header" style="padding: 8px 16px; background: #1e1e1e; color: #fff; display: flex; justify-content: space-between; align-items: center;">
        <div>
          <span style="font-weight: bold;">Terminal</span>
          <%= if @session_id do %>
            <span style="margin-left: 12px; font-size: 12px; opacity: 0.7;">
              Session: <%= String.slice(@session_id, 0, 8) %>...
            </span>
          <% end %>
        </div>
        <div style="display: flex; gap: 12px; align-items: center;">
          <%= if @status == :ready do %>
            <span style="font-size: 12px; opacity: 0.7;">Port: <%= @port %></span>
            <span style="color: #4ade80;">Connected</span>
          <% end %>
          <%= if @status == :connecting do %>
            <span style="color: #fbbf24;">Connecting...</span>
          <% end %>
          <%= if @status == :error do %>
            <span style="color: #f87171;">Error</span>
          <% end %>
        </div>
      </div>

      <div class="ttyd-body" style="flex: 1; background: #1e1e1e;">
        <%= case @status do %>
          <% :ready -> %>
            <iframe
              src={"http://localhost:#{@port}"}
              style="width: 100%; height: 100%; border: none;"
              allow="clipboard-read; clipboard-write"
            />
          <% :connecting -> %>
            <div style="display: flex; align-items: center; justify-content: center; height: 100%; color: #fff;">
              <div style="text-align: center;">
                <div style="font-size: 24px; margin-bottom: 16px;">Starting terminal...</div>
                <div style="opacity: 0.7;">Establishing connection</div>
              </div>
            </div>
          <% :error -> %>
            <div style="display: flex; align-items: center; justify-content: center; height: 100%; color: #fff;">
              <div style="text-align: center; max-width: 400px;">
                <div style="font-size: 24px; margin-bottom: 16px; color: #f87171;">Terminal Error</div>
                <div style="opacity: 0.9; margin-bottom: 24px;"><%= @error %></div>
                <button
                  phx-click="retry"
                  style="padding: 8px 24px; background: #3b82f6; color: white; border: none; border-radius: 4px; cursor: pointer;"
                >
                  Retry
                </button>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("retry", _params, socket) do
    # Stop existing session if any
    if socket.assigns[:session_id] do
      SessionManager.stop_session(socket.assigns.session_id)
    end

    case start_terminal_session() do
      {:ok, session_id, port} ->
        {:noreply,
         socket
         |> assign(:session_id, session_id)
         |> assign(:port, port)
         |> assign(:status, :ready)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:status, :error)
         |> assign(:error, "Failed to start terminal: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp start_terminal_session do
    config = Application.get_env(:events, :ttyd, [])

    opts = [
      command: Keyword.get(config, :command, default_command()),
      writable: Keyword.get(config, :writable, true),
      cwd: Keyword.get(config, :cwd)
    ]

    SessionManager.start_session(self(), opts)
  end

  defp default_command do
    case :os.type() do
      {:unix, :darwin} -> System.get_env("SHELL", "/bin/zsh")
      {:unix, _} -> System.get_env("SHELL", "/bin/bash")
      {:win32, _} -> "cmd.exe"
    end
  end
end
