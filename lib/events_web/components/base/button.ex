defmodule EventsWeb.Components.Base.Button do
  @moduledoc """
  Button component for user interactions.

  Supports multiple variants, sizes, and states with shared utility patterns.

  ## Examples

      <.button>Click me</.button>
      <.button variant="primary" size="lg">Large Primary</.button>
      <.button variant="destructive" size="sm">Delete</.button>
      <.button variant="ghost" disabled>Disabled</.button>
      <.button variant="link" navigate={~p"/home"}>Home</.button>

  ## Variants

  - `default` - Standard dark button
  - `primary` - Primary action (blue)
  - `secondary` - Secondary action (light gray)
  - `outline` - Bordered button
  - `ghost` - Minimal styling
  - `destructive` - Dangerous actions (red)
  - `link` - Link-styled button

  ## Sizes

  - `sm` - Small (h-8, text-xs)
  - `default` - Standard (h-10, text-sm)
  - `lg` - Large (h-12, text-base)
  - `icon` - Square icon button (10x10)
  - `icon-sm` - Small icon button (8x8)
  - `icon-lg` - Large icon button (12x12)
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  attr :variant, :string,
    default: "default",
    values: ~w(default primary secondary outline ghost destructive link)

  attr :size, :string, default: "default", values: ~w(default sm lg icon icon-sm icon-lg)
  attr :class, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(navigate patch href phx-click phx-value-* form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={
        Utils.classes([
          Utils.interactive_base(),
          "whitespace-nowrap gap-2",
          Utils.variant(@variant, Utils.button_variants()),
          Utils.variant(@size, Utils.size_variants()),
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end
