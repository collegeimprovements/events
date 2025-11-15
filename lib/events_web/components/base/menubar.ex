defmodule EventsWeb.Components.Base.Menubar do
  @moduledoc """
  Menubar component for application menus.

  ## Examples

      <.menubar>
        <:menu label="File">
          <:item>New</:item>
          <:item>Open</:item>
          <:separator />
          <:item>Exit</:item>
        </:menu>
        <:menu label="Edit">
          <:item>Cut</:item>
          <:item>Copy</:item>
          <:item>Paste</:item>
        </:menu>
      </.menubar>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :class, :string, default: nil
  attr :rest, :global

  slot :menu, required: true do
    attr :label, :string, required: true

    slot :item do
      attr :phx_click, :string
      attr :disabled, :boolean
    end

    slot :separator
  end

  def menubar(assigns) do
    ~H"""
    <div
      role="menubar"
      class={
        classes([
          "flex h-10 items-center space-x-1 rounded-md border border-zinc-200 bg-white p-1",
          @class
        ])
      }
      {@rest}
    >
      <%= for menu <- @menu do %>
        <div class="relative">
          <button
            type="button"
            role="menuitem"
            aria-haspopup="true"
            phx-click={toggle_menu(menu.label)}
            class={
              classes([
                "inline-flex items-center rounded-sm px-3 py-1.5",
                "text-sm font-medium transition-colors",
                "hover:bg-zinc-100 focus:bg-zinc-100",
                "focus:outline-none"
              ])
            }
          >
            <%= menu.label %>
          </button>
          <div
            id={"menu-#{menu.label}"}
            role="menu"
            class={
              classes([
                "absolute left-0 z-50 mt-1 hidden w-48 origin-top-left rounded-md",
                "border border-zinc-200 bg-white shadow-lg",
                "animate-in fade-in-0 zoom-in-95"
              ])
            }
          >
            <div class="py-1">
              <%= for entry <- (menu[:item] || []) ++ (menu[:separator] || []) do %>
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
      <% end %>
    </div>
    """
  end

  defp toggle_menu(label) do
    JS.toggle(to: "#menu-#{label}", in: "fade-in-scale", out: "fade-out-scale")
  end
end
