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
  alias EventsWeb.Components.Base.Utils

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
      <div role="dialog" class={card_classes(@side, @align, @class)}>
        <%= render_slot(@content) %>
      </div>
    </div>
    """
  end

  defp card_classes(side, align, custom_class) do
    [
      "absolute z-50 hidden w-80 rounded-md border border-zinc-200 bg-white p-4 shadow-md",
      "animate-in fade-in-0 zoom-in-95 group-hover:block",
      Utils.position_classes(side, align),
      custom_class
    ]
    |> Utils.classes()
  end
end
