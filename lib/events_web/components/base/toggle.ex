defmodule EventsWeb.Components.Base.Toggle do
  @moduledoc """
  Toggle component for two-state buttons.

  ## Examples

      <.toggle>
        <span>Bold</span>
      </.toggle>

      <.toggle pressed variant="outline">
        <span>Italic</span>
      </.toggle>

      <.toggle size="sm" disabled>
        <span>Underline</span>
      </.toggle>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :pressed, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :variant, :string, default: "default", values: ~w(default outline)
  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  slot :inner_block, required: true

  def toggle(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-pressed={to_string(@pressed)}
      disabled={@disabled}
      class={
        classes([
          "inline-flex items-center justify-center rounded-md font-medium",
          "transition-colors duration-150",
          "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
          "disabled:pointer-events-none disabled:opacity-50",
          variant_classes(@variant, @pressed),
          size_classes(@size),
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  defp variant_classes("default", false),
    do: "bg-transparent hover:bg-zinc-100 hover:text-zinc-900"

  defp variant_classes("default", true),
    do: "bg-zinc-100 text-zinc-900"

  defp variant_classes("outline", false),
    do: "border border-zinc-300 bg-transparent hover:bg-zinc-100 hover:text-zinc-900"

  defp variant_classes("outline", true),
    do: "border border-zinc-300 bg-zinc-100 text-zinc-900"

  defp size_classes("default"), do: "h-10 px-3 text-sm"
  defp size_classes("sm"), do: "h-8 px-2 text-xs"
  defp size_classes("lg"), do: "h-12 px-4 text-base"
end
