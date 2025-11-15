defmodule EventsWeb.Components.Base.Sidebar do
  @moduledoc """
  Sidebar component for navigation and layout.

  ## Examples

      <.sidebar>
        <:header>
          <h2 class="text-lg font-semibold">Navigation</h2>
        </:header>
        <:content>
          <nav>
            <.link navigate={~p"/"}>Dashboard</.link>
            <.link navigate={~p"/settings"}>Settings</.link>
          </nav>
        </:content>
        <:footer>
          <p class="text-xs text-zinc-500">© 2024</p>
        </:footer>
      </.sidebar>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :side, :string, default: "left", values: ~w(left right)
  attr :collapsible, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :header
  slot :content, required: true
  slot :footer

  def sidebar(assigns) do
    ~H"""
    <aside
      class={
        classes([
          "flex flex-col border-r border-zinc-200 bg-white",
          if(@side == "right", do: "border-l border-r-0", else: ""),
          if(@collapsed, do: "w-16", else: "w-64"),
          "transition-all duration-300",
          @class
        ])
      }
      {@rest}
    >
      <div :if={@header != []} class="border-b border-zinc-200 p-4">
        <%= render_slot(@header) %>
      </div>
      <div class="flex-1 overflow-y-auto p-4">
        <%= render_slot(@content) %>
      </div>
      <div :if={@footer != []} class="border-t border-zinc-200 p-4">
        <%= render_slot(@footer) %>
      </div>
      <button
        :if={@collapsible}
        type="button"
        phx-click="toggle-sidebar"
        class="absolute -right-3 top-4 rounded-full border border-zinc-200 bg-white p-1 shadow-sm"
        aria-label="Toggle sidebar"
      >
        <svg
          class={classes(["h-4 w-4 transition-transform", if(@collapsed, do: "rotate-180", else: "")])}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
            clip-rule="evenodd"
          />
        </svg>
      </button>
    </aside>
    """
  end
end
