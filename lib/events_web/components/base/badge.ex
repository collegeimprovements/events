defmodule EventsWeb.Components.Base.Badge do
  @moduledoc """
  Badge component for displaying labels and status indicators.

  Uses shared variant system for consistent styling across status indicators.

  ## Examples

      <.badge>Default</.badge>
      <.badge variant="success">Success</.badge>
      <.badge variant="warning">Warning</.badge>
      <.badge variant="error">Error</.badge>
      <.badge variant="outline" size="lg">Outline Large</.badge>

  ## Variants

  - `default` - Dark badge
  - `success` - Green background
  - `warning` - Yellow background
  - `error` - Red background
  - `info` - Blue background
  - `outline` - Bordered badge
  - `secondary` - Light gray background

  ## Sizes

  - `sm` - Extra small (text-[10px])
  - `default` - Standard (text-xs)
  - `lg` - Large (text-sm)
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

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
        Utils.classes([
          "inline-flex items-center justify-center",
          "rounded-full font-medium transition-colors",
          Utils.variant(@variant, Utils.badge_variants()),
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

  defp size_classes("default"), do: "px-2.5 py-0.5 text-xs"
  defp size_classes("sm"), do: "px-2 py-0.5 text-[10px]"
  defp size_classes("lg"), do: "px-3 py-1 text-sm"
end
