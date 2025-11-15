defmodule EventsWeb.Components.Base.Command do
  @moduledoc """
  Command component for command palette / search.

  ## Examples

      <.command id="cmd-palette" placeholder="Type a command...">
        <:group label="Suggestions">
          <:item>Calendar</:item>
          <:item>Search Emoji</:item>
        </:group>
        <:group label="Settings">
          <:item>Profile</:item>
          <:item>Billing</:item>
        </:group>
      </.command>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :id, :string, required: true
  attr :placeholder, :string, default: "Type a command or search..."
  attr :class, :string, default: nil
  attr :rest, :global

  slot :group do
    attr :label, :string

    slot :item do
      attr :phx_click, :string
      attr :icon, :string
    end
  end

  def command(assigns) do
    ~H"""
    <div
      id={@id}
      class={
        classes([
          "flex flex-col overflow-hidden rounded-lg border border-zinc-200 bg-white",
          @class
        ])
      }
      phx-hook="Command"
      {@rest}
    >
      <div class="flex items-center border-b border-zinc-200 px-3">
        <svg
          class="mr-2 h-4 w-4 shrink-0 opacity-50"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z"
            clip-rule="evenodd"
          />
        </svg>
        <input
          type="text"
          placeholder={@placeholder}
          class={
            classes([
              "flex h-11 w-full rounded-md bg-transparent py-3 text-sm outline-none",
              "placeholder:text-zinc-500",
              "disabled:cursor-not-allowed disabled:opacity-50"
            ])
          }
        />
      </div>
      <div class="max-h-[300px] overflow-y-auto overflow-x-hidden">
        <%= for group <- @group do %>
          <div class="overflow-hidden p-1">
            <div :if={group[:label]} class="px-2 py-1.5 text-xs font-medium text-zinc-500">
              <%= group.label %>
            </div>
            <%= for item <- group[:item] || [] do %>
              <button
                type="button"
                phx-click={item[:phx_click]}
                class={
                  classes([
                    "relative flex w-full cursor-pointer select-none items-center rounded-sm",
                    "px-2 py-1.5 text-sm outline-none",
                    "hover:bg-zinc-100 focus:bg-zinc-100",
                    "disabled:pointer-events-none disabled:opacity-50"
                  ])
                }
              >
                <%= if item[:icon] do %>
                  <span class="mr-2"><%= item.icon %></span>
                <% end %>
                <%= render_slot(item) %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
