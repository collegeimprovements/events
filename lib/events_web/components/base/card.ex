defmodule EventsWeb.Components.Base.Card do
  @moduledoc """
  Card component for containing related content.

  ## Examples

      <.card>
        <:header>
          <:title>Card Title</:title>
          <:description>Card description goes here</:description>
        </:header>
        <:content>
          Card content
        </:content>
        <:footer>
          <.button>Action</.button>
        </:footer>
      </.card>

      <.card class="w-96">
        <:content>Simple card with just content</:content>
      </.card>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :class, :string, default: nil
  attr :rest, :global

  slot :header do
    slot :title
    slot :description
  end

  slot :content
  slot :footer

  def card(assigns) do
    ~H"""
    <div
      class={
        classes([
          "rounded-lg border border-zinc-200 bg-white text-zinc-900 shadow-sm",
          @class
        ])
      }
      {@rest}
    >
      <div :if={@header != []} class="flex flex-col space-y-1.5 p-6">
        <%= for header <- @header do %>
          <h3 :if={header[:title] != []} class="text-2xl font-semibold leading-none tracking-tight">
            <%= render_slot(header, :title) %>
          </h3>
          <p :if={header[:description] != []} class="text-sm text-zinc-500">
            <%= render_slot(header, :description) %>
          </p>
        <% end %>
      </div>
      <div :if={@content != []} class="p-6 pt-0">
        <%= render_slot(@content) %>
      </div>
      <div :if={@footer != []} class="flex items-center border-t border-zinc-200 p-6 pt-0">
        <%= render_slot(@footer) %>
      </div>
    </div>
    """
  end
end
