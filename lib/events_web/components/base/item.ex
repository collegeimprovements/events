defmodule EventsWeb.Components.Base.Item do
  @moduledoc """
  Item component - versatile container for displaying content.

  ## Examples

      <.item>
        <:leading>
          <.avatar src="/user.jpg" />
        </:leading>
        <:content>
          <:title>John Doe</:title>
          <:description>Software Engineer</:description>
        </:content>
        <:trailing>
          <.button size="sm">View</.button>
        </:trailing>
      </.item>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :class, :string, default: nil
  attr :clickable, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  slot :leading
  slot :content do
    slot :title
    slot :description
  end

  slot :trailing

  def item(assigns) do
    ~H"""
    <div
      class={
        classes([
          "flex items-center gap-3 rounded-md p-3",
          if(@clickable, do: "cursor-pointer hover:bg-zinc-50 transition-colors", else: ""),
          @class
        ])
      }
      {@rest}
    >
      <div :if={@leading != []} class="shrink-0">
        <%= render_slot(@leading) %>
      </div>
      <div :if={@content != []} class="flex-1 min-w-0">
        <%= for content <- @content do %>
          <div :if={content[:title] != []} class="font-medium text-sm text-zinc-900 truncate">
            <%= render_slot(content, :title) %>
          </div>
          <div :if={content[:description] != []} class="text-xs text-zinc-500 truncate">
            <%= render_slot(content, :description) %>
          </div>
        <% end %>
      </div>
      <div :if={@trailing != []} class="shrink-0">
        <%= render_slot(@trailing) %>
      </div>
    </div>
    """
  end
end
