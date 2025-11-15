defmodule EventsWeb.Components.Base.Resizable do
  @moduledoc """
  Resizable component for adjustable panel layouts.

  ## Examples

      <.resizable id="main-layout" direction="horizontal">
        <:panel size={30}>
          Sidebar content
        </:panel>
        <:panel size={70}>
          Main content
        </:panel>
      </.resizable>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :id, :string, required: true
  attr :direction, :string, default: "horizontal", values: ~w(horizontal vertical)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :panel, required: true do
    attr :size, :integer
    attr :min_size, :integer
  end

  def resizable(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Resizable"
      class={
        classes([
          "flex",
          if(@direction == "horizontal", do: "flex-row", else: "flex-col"),
          @class
        ])
      }
      {@rest}
    >
      <%= for {panel, index} <- Enum.with_index(@panel) do %>
        <div
          class="relative"
          style={"flex: #{panel[:size] || 1}; min-width: #{panel[:min_size] || 0}px;"}
        >
          <%= render_slot(panel) %>
        </div>
        <%= if index < length(@panel) - 1 do %>
          <div
            class={
              classes([
                "relative flex-shrink-0 bg-zinc-200",
                "hover:bg-zinc-300 cursor-col-resize",
                if(@direction == "horizontal", do: "w-1", else: "h-1 cursor-row-resize")
              ])
            }
            data-resize-handle
          />
        <% end %>
      <% end %>
    </div>
    """
  end
end
