defmodule EventsWeb.Components.Base.Tooltip do
  @moduledoc """
  Tooltip component for displaying helpful information on hover.

  Uses shared positioning utilities with modern CSS features.

  ## Examples

      <.tooltip content="Click to save">
        <.button>Save</.button>
      </.tooltip>

      <.tooltip content="Delete this item" side="right">
        <.button variant="destructive">Delete</.button>
      </.tooltip>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  attr :content, :string, required: true
  attr :side, :string, default: "top", values: ~w(top bottom left right)
  attr :align, :string, default: "center", values: ~w(start center end)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <div class="group relative inline-block" {@rest}>
      <%= render_slot(@inner_block) %>
      <div
        role="tooltip"
        class={tooltip_classes(@side, @align, @class)}
      >
        <%= @content %>
      </div>
    </div>
    """
  end

  defp tooltip_classes(side, align, custom_class) do
    [
      "pointer-events-none absolute z-50 hidden px-3 py-1.5",
      "rounded-md bg-zinc-900 text-xs text-zinc-50 shadow-md",
      "transition-opacity duration-200",
      "group-hover:block group-focus-within:block",
      Utils.animation_in(),
      Utils.position_classes(side, align),
      custom_class
    ]
    |> Utils.classes()
  end
end
