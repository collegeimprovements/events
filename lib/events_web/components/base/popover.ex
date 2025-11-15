defmodule EventsWeb.Components.Base.Popover do
  @moduledoc """
  Popover component for displaying floating content.

  ## Examples

      <.popover id="help-popover">
        <:trigger>
          <.button variant="ghost">?</.button>
        </:trigger>
        <:content>
          <p class="text-sm">This is helpful information.</p>
        </:content>
      </.popover>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :side, :string, default: "bottom", values: ~w(top bottom left right)
  attr :align, :string, default: "center", values: ~w(start center end)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger, required: true
  slot :content, required: true

  def popover(assigns) do
    ~H"""
    <div class="relative inline-block">
      <div phx-click={toggle_popover(@id)}>
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={@id}
        role="dialog"
        class={
          classes([
            "absolute z-50 w-72 rounded-md border border-zinc-200 bg-white p-4 shadow-md",
            "animate-in fade-in-0 zoom-in-95",
            if(@open, do: "block", else: "hidden"),
            position_classes(@side, @align),
            @class
          ])
        }
        {@rest}
      >
        <%= render_slot(@content) %>
      </div>
    </div>
    """
  end

  defp position_classes("top", "center"), do: "bottom-full left-1/2 -translate-x-1/2 mb-2"
  defp position_classes("top", "start"), do: "bottom-full left-0 mb-2"
  defp position_classes("top", "end"), do: "bottom-full right-0 mb-2"
  defp position_classes("bottom", "center"), do: "top-full left-1/2 -translate-x-1/2 mt-2"
  defp position_classes("bottom", "start"), do: "top-full left-0 mt-2"
  defp position_classes("bottom", "end"), do: "top-full right-0 mt-2"
  defp position_classes("left", "center"), do: "right-full top-1/2 -translate-y-1/2 mr-2"
  defp position_classes("right", "center"), do: "left-full top-1/2 -translate-y-1/2 ml-2"
  defp position_classes(_, _), do: "top-full left-1/2 -translate-x-1/2 mt-2"

  defp toggle_popover(id) do
    JS.toggle(to: "##{id}", in: "fade-in-scale", out: "fade-out-scale")
  end
end
