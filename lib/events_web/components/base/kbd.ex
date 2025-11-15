defmodule EventsWeb.Components.Base.Kbd do
  @moduledoc """
  Kbd component for displaying keyboard shortcuts.

  ## Examples

      <.kbd>⌘K</.kbd>
      <.kbd>Ctrl+C</.kbd>
      <.kbd size="sm">Esc</.kbd>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def kbd(assigns) do
    ~H"""
    <kbd
      class={
        classes([
          "inline-flex items-center justify-center",
          "rounded border border-zinc-200 bg-zinc-100",
          "font-mono font-medium text-zinc-900",
          "shadow-sm",
          size_classes(@size),
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </kbd>
    """
  end

  defp size_classes("default"), do: "px-2 py-1 text-xs"
  defp size_classes("sm"), do: "px-1.5 py-0.5 text-[10px]"
  defp size_classes("lg"), do: "px-2.5 py-1.5 text-sm"
end
