defmodule EventsWeb.PageController do
  use EventsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
