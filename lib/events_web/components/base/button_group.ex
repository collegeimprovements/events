defmodule EventsWeb.Components.Base.ButtonGroup do
  @moduledoc """
  ButtonGroup component for grouping related buttons.

  ## Examples

      <.button_group>
        <.button>First</.button>
        <.button>Second</.button>
        <.button>Third</.button>
      </.button_group>

      <.button_group orientation="vertical">
        <.button>Top</.button>
        <.button>Middle</.button>
        <.button>Bottom</.button>
      </.button_group>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :orientation, :string, default: "horizontal", values: ~w(horizontal vertical)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def button_group(assigns) do
    ~H"""
    <div
      role="group"
      class={
        classes([
          "inline-flex",
          if(@orientation == "horizontal", do: "flex-row", else: "flex-col"),
          "[&>*:first-child]:rounded-l-md [&>*:first-child]:rounded-r-none",
          "[&>*:last-child]:rounded-r-md [&>*:last-child]:rounded-l-none",
          "[&>*:not(:first-child):not(:last-child)]:rounded-none",
          "[&>*:not(:first-child)]:-ml-px",
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
