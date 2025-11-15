defmodule EventsWeb.Components.Base.DropdownMenu do
  @moduledoc """
  DropdownMenu component for action menus.

  ## Examples

      <.dropdown_menu id="user-menu">
        <:trigger>
          <.button variant="outline">Options</.button>
        </:trigger>
        <:item>Profile</:item>
        <:item>Settings</:item>
        <:separator />
        <:item>Logout</:item>
      </.dropdown_menu>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger, required: true

  slot :item do
    attr :phx_click, :string
    attr :disabled, :boolean
  end

  slot :separator

  def dropdown_menu(assigns) do
    ~H"""
    <div class="relative inline-block text-left">
      <div phx-click={toggle_dropdown(@id)}>
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={@id}
        role="menu"
        class={
          classes([
            "absolute right-0 z-50 mt-2 w-56 origin-top-right rounded-md",
            "border border-zinc-200 bg-white shadow-lg",
            "animate-in fade-in-0 zoom-in-95",
            if(@open, do: "block", else: "hidden"),
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

  defp toggle_dropdown(id) do
    JS.toggle(to: "##{id}", in: "fade-in-scale", out: "fade-out-scale")
  end
end
