defmodule EventsWeb.Components.Base.HoverCard do
  @moduledoc """
  HoverCard component for rich previews on hover.

  ## Examples

      <.hover_card>
        <:trigger>
          <.link>@username</.link>
        </:trigger>
        <:content>
          <div class="flex gap-4">
            <.avatar src="/avatar.jpg" />
            <div>
              <h4 class="font-semibold">Username</h4>
              <p class="text-sm text-zinc-500">Bio information</p>
            </div>
          </div>
        </:content>
      </.hover_card>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :side, :string, default: "bottom", values: ~w(top bottom left right)
  attr :align, :string, default: "center", values: ~w(start center end)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger, required: true
  slot :content, required: true

  def hover_card(assigns) do
    ~H"""
    <div class="group relative inline-block" {@rest}>
      <%= render_slot(@trigger) %>
      <div
        role="dialog"
        class={
          classes([
            "absolute z-50 hidden w-80 rounded-md border border-zinc-200 bg-white p-4 shadow-md",
            "animate-in fade-in-0 zoom-in-95",
            "group-hover:block",
            position_classes(@side, @align),
            @class
          ])
        }
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
end
