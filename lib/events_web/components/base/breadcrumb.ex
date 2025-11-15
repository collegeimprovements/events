defmodule EventsWeb.Components.Base.Breadcrumb do
  @moduledoc """
  Breadcrumb component for navigation hierarchy.

  ## Examples

      <.breadcrumb>
        <:item navigate={~p"/"}>Home</:item>
        <:item navigate={~p"/docs"}>Docs</:item>
        <:item>Current Page</:item>
      </.breadcrumb>

      <.breadcrumb separator="/">
        <:item href="/home">Home</:item>
        <:item>Products</:item>
      </.breadcrumb>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :separator, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :item, required: true do
    attr :navigate, :string
    attr :patch, :string
    attr :href, :string
  end

  def breadcrumb(assigns) do
    ~H"""
    <nav aria-label="Breadcrumb" class={classes([@class])} {@rest}>
      <ol class="flex items-center space-x-2 text-sm text-zinc-600">
        <%= for {item, index} <- Enum.with_index(@item) do %>
          <li class="flex items-center gap-2">
            <%= if index > 0 do %>
              <span class="text-zinc-400" aria-hidden="true">
                <%= @separator || render_chevron() %>
              </span>
            <% end %>
            <%= if item[:navigate] || item[:patch] || item[:href] do %>
              <.link
                navigate={item[:navigate]}
                patch={item[:patch]}
                href={item[:href]}
                class="hover:text-zinc-900 transition-colors"
              >
                <%= render_slot(item) %>
              </.link>
            <% else %>
              <span class="font-medium text-zinc-900" aria-current="page">
                <%= render_slot(item) %>
              </span>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end

  defp render_chevron do
    Phoenix.HTML.raw("""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="h-4 w-4"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <path
        fill-rule="evenodd"
        d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """)
  end
end
