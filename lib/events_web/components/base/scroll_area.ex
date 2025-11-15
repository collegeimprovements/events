defmodule EventsWeb.Components.Base.ScrollArea do
  @moduledoc """
  ScrollArea component with custom scrollbars.

  ## Examples

      <.scroll_area class="h-72 w-96">
        <div class="p-4">
          Long content that scrolls...
        </div>
      </.scroll_area>

      <.scroll_area orientation="horizontal" class="w-full">
        <div class="flex gap-4 p-4">
          <div>Item 1</div>
          <div>Item 2</div>
          <!-- More items -->
        </div>
      </.scroll_area>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :orientation, :string, default: "vertical", values: ~w(vertical horizontal both)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def scroll_area(assigns) do
    ~H"""
    <div
      class={
        classes([
          "relative overflow-auto",
          scrollbar_classes(@orientation),
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp scrollbar_classes("vertical"),
    do:
      "[&::-webkit-scrollbar]:w-2 [&::-webkit-scrollbar-track]:bg-zinc-100 [&::-webkit-scrollbar-thumb]:bg-zinc-300 [&::-webkit-scrollbar-thumb]:rounded-full hover:[&::-webkit-scrollbar-thumb]:bg-zinc-400"

  defp scrollbar_classes("horizontal"),
    do:
      "[&::-webkit-scrollbar]:h-2 [&::-webkit-scrollbar-track]:bg-zinc-100 [&::-webkit-scrollbar-thumb]:bg-zinc-300 [&::-webkit-scrollbar-thumb]:rounded-full hover:[&::-webkit-scrollbar-thumb]:bg-zinc-400"

  defp scrollbar_classes("both"),
    do:
      "[&::-webkit-scrollbar]:w-2 [&::-webkit-scrollbar]:h-2 [&::-webkit-scrollbar-track]:bg-zinc-100 [&::-webkit-scrollbar-thumb]:bg-zinc-300 [&::-webkit-scrollbar-thumb]:rounded-full hover:[&::-webkit-scrollbar-thumb]:bg-zinc-400"
end
