defmodule EventsWeb.Plugs.TtydProxy do
  @moduledoc """
  Plug that proxies requests to a ttyd terminal server.

  ttyd handles its own WebSocket connections for the terminal,
  so this plug redirects browser requests to the ttyd server.

  ## Usage

      # In router.ex
      forward "/terminal", EventsWeb.Plugs.TtydProxy, port: 7681

  """

  @behaviour Plug

  import Plug.Conn

  @default_port 7681

  @impl true
  def init(opts) do
    %{
      port: Keyword.get(opts, :port, @default_port),
      host: Keyword.get(opts, :host, "localhost"),
      ssl: Keyword.get(opts, :ssl, false)
    }
  end

  @impl true
  def call(conn, opts) do
    scheme = if opts.ssl, do: "https", else: "http"

    # Build the target URL
    # Strip the forward path prefix and keep the rest
    path = conn.path_info |> Enum.join("/")
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""

    target_url = "#{scheme}://#{opts.host}:#{opts.port}/#{path}#{query}"

    conn
    |> put_resp_header("location", target_url)
    |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
    |> send_resp(:temporary_redirect, "")
    |> halt()
  end
end
