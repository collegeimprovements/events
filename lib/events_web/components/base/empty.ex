defmodule EventsWeb.Components.Base.Empty do
  @moduledoc """
  Empty state component for displaying empty data states.

  ## Examples

      <.empty>
        <:title>No results found</:title>
        <:description>Try adjusting your search criteria</:description>
      </.empty>

      <.empty>
        <:icon>
          <.icon name="hero-inbox" class="h-12 w-12" />
        </:icon>
        <:title>No messages</:title>
        <:description>Start a conversation to see messages here</:description>
        <:action>
          <.button>New message</.button>
        </:action>
      </.empty>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :class, :string, default: nil
  attr :rest, :global

  slot :icon
  slot :title
  slot :description
  slot :action

  def empty(assigns) do
    ~H"""
    <div
      class={
        classes([
          "flex flex-col items-center justify-center",
          "rounded-lg border border-dashed border-zinc-300",
          "p-8 text-center",
          @class
        ])
      }
      {@rest}
    >
      <div :if={@icon != []} class="mb-4 text-zinc-400">
        <%= render_slot(@icon) %>
      </div>
      <h3 :if={@title != []} class="mb-2 text-lg font-semibold text-zinc-900">
        <%= render_slot(@title) %>
      </h3>
      <p :if={@description != []} class="mb-4 max-w-sm text-sm text-zinc-600">
        <%= render_slot(@description) %>
      </p>
      <div :if={@action != []} class="flex gap-2">
        <%= render_slot(@action) %>
      </div>
    </div>
    """
  end
end
