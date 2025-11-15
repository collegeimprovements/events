defmodule EventsWeb.Components.Base.NavigationMenu do
  @moduledoc """
  NavigationMenu component for site navigation.

  ## Examples

      <.navigation_menu>
        <:item navigate={~p"/"}>Home</:item>
        <:item navigate={~p"/about"}>About</:item>
        <:item navigate={~p"/contact"}>Contact</:item>
      </.navigation_menu>

      <.navigation_menu orientation="vertical">
        <:item navigate={~p"/dashboard"}>Dashboard</:item>
        <:item navigate={~p"/settings"}>Settings</:item>
      </.navigation_menu>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :orientation, :string, default: "horizontal", values: ~w(horizontal vertical)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :item, required: true do
    attr :navigate, :string
    attr :patch, :string
    attr :href, :string
    attr :active, :boolean
  end

  def navigation_menu(assigns) do
    ~H"""
    <nav
      role="navigation"
      class={
        classes([
          "flex",
          if(@orientation == "horizontal", do: "flex-row space-x-1", else: "flex-col space-y-1"),
          @class
        ])
      }
      {@rest}
    >
      <%= for item <- @item do %>
        <.link
          navigate={item[:navigate]}
          patch={item[:patch]}
          href={item[:href]}
          class={
            classes([
              "inline-flex items-center justify-center rounded-md px-4 py-2",
              "text-sm font-medium transition-colors",
              "hover:bg-zinc-100 hover:text-zinc-900",
              "focus:bg-zinc-100 focus:text-zinc-900 focus:outline-none",
              "disabled:pointer-events-none disabled:opacity-50",
              if(item[:active], do: "bg-zinc-100 text-zinc-900", else: "text-zinc-600")
            ])
          }
        >
          <%= render_slot(item) %>
        </.link>
      <% end %>
    </nav>
    """
  end
end
