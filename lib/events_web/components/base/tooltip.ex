defmodule EventsWeb.Components.Base.Tooltip do
  @moduledoc """
  Tooltip component for displaying helpful information on hover.

  ## Examples

      <.tooltip content="Click to save">
        <.button>Save</.button>
      </.tooltip>

      <.tooltip content="Delete this item" side="right">
        <.button variant="destructive">Delete</.button>
      </.tooltip>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :content, :string, required: true
  attr :side, :string, default: "top", values: ~w(top bottom left right)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <div class="group relative inline-block" {@rest}>
      <%= render_slot(@inner_block) %>
      <div
        role="tooltip"
        class={
          classes([
            "pointer-events-none absolute z-50 hidden px-3 py-1.5",
            "rounded-md bg-zinc-900 text-xs text-zinc-50 shadow-md",
            "animate-in fade-in-0 zoom-in-95",
            "group-hover:block",
            position_classes(@side),
            @class
          ])
        }
      >
        <%= @content %>
      </div>
    </div>
    """
  end

  defp position_classes("top"), do: "bottom-full left-1/2 -translate-x-1/2 mb-2"
  defp position_classes("bottom"), do: "top-full left-1/2 -translate-x-1/2 mt-2"
  defp position_classes("left"), do: "right-full top-1/2 -translate-y-1/2 mr-2"
  defp position_classes("right"), do: "left-full top-1/2 -translate-y-1/2 ml-2"
end
