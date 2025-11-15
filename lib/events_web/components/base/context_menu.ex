defmodule EventsWeb.Components.Base.ContextMenu do
  @moduledoc """
  ContextMenu component for right-click menus.

  ## Examples

      <.context_menu id="file-context">
        <:trigger>
          <div class="p-4 border rounded">Right-click me</div>
        </:trigger>
        <:item>Open</:item>
        <:item>Copy</:item>
        <:separator />
        <:item>Delete</:item>
      </.context_menu>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger, required: true

  slot :item do
    attr :phx_click, :string
    attr :disabled, :boolean
  end

  slot :separator

  def context_menu(assigns) do
    ~H"""
    <div class="relative" phx-hook="ContextMenu" id={"#{@id}-wrapper"}>
      <div>
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={@id}
        role="menu"
        class={
          classes([
            "absolute z-50 hidden w-56 rounded-md border border-zinc-200",
            "bg-white shadow-lg",
            "animate-in fade-in-0 zoom-in-95",
            @class
          ])
        }
        {@rest}
      >
        <div class="py-1" role="none">
          <%= for entry <- @item ++ @separator do %>
            <%= if entry == :separator || Map.get(entry, :__slot__) == :separator do %>
              <div class="my-1 h-px bg-zinc-200" role="separator" />
            <% else %>
              <button
                type="button"
                role="menuitem"
                phx-click={entry[:phx_click]}
                disabled={entry[:disabled] || false}
                class={
                  classes([
                    "w-full px-4 py-2 text-left text-sm text-zinc-900",
                    "hover:bg-zinc-100 focus:bg-zinc-100",
                    "disabled:cursor-not-allowed disabled:opacity-50"
                  ])
                }
              >
                <%= render_slot(entry) %>
              </button>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
