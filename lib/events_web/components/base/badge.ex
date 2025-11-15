defmodule EventsWeb.Components.Base.Badge do
  @moduledoc """
  Badge component for displaying labels and status indicators.

  ## Examples

      <.badge>Default</.badge>
      <.badge variant="success">Success</.badge>
      <.badge variant="warning">Warning</.badge>
      <.badge variant="error">Error</.badge>
      <.badge variant="outline">Outline</.badge>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :variant, :string,
    default: "default",
    values: ~w(default success warning error info outline secondary)

  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      class={
        classes([
          "inline-flex items-center justify-center",
          "rounded-full font-medium",
          "transition-colors",
          variant_classes(@variant),
          size_classes(@size),
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp variant_classes("default"),
    do: "bg-zinc-900 text-zinc-50 hover:bg-zinc-800"

  defp variant_classes("success"),
    do: "bg-green-100 text-green-800 hover:bg-green-200"

  defp variant_classes("warning"),
    do: "bg-yellow-100 text-yellow-800 hover:bg-yellow-200"

  defp variant_classes("error"),
    do: "bg-red-100 text-red-800 hover:bg-red-200"

  defp variant_classes("info"),
    do: "bg-blue-100 text-blue-800 hover:bg-blue-200"

  defp variant_classes("outline"),
    do: "border border-zinc-300 bg-white text-zinc-900 hover:bg-zinc-50"

  defp variant_classes("secondary"),
    do: "bg-zinc-100 text-zinc-900 hover:bg-zinc-200"

  defp size_classes("default"), do: "px-2.5 py-0.5 text-xs"
  defp size_classes("sm"), do: "px-2 py-0.5 text-[10px]"
  defp size_classes("lg"), do: "px-3 py-1 text-sm"
end
