defmodule EventsWeb.Components.Base.Slider do
  @moduledoc """
  Slider component for selecting values from a range.

  ## Examples

      <.slider name="volume" value={50} />
      <.slider name="opacity" min={0} max={100} step={1} value={75} />
      <.slider name="range" disabled />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :name, :string, required: true
  attr :value, :integer, default: 50
  attr :min, :integer, default: 0
  attr :max, :integer, default: 100
  attr :step, :integer, default: 1
  attr :disabled, :boolean, default: false
  attr :show_value, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def slider(assigns) do
    ~H"""
    <div class="relative w-full" phx-hook="Slider">
      <input
        type="range"
        name={@name}
        value={@value}
        min={@min}
        max={@max}
        step={@step}
        disabled={@disabled}
        class={
          classes([
            "h-2 w-full cursor-pointer appearance-none rounded-lg bg-zinc-200",
            "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "[&::-webkit-slider-thumb]:h-5 [&::-webkit-slider-thumb]:w-5",
            "[&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full",
            "[&::-webkit-slider-thumb]:bg-zinc-900 [&::-webkit-slider-thumb]:shadow",
            "[&::-webkit-slider-thumb]:transition-all [&::-webkit-slider-thumb]:duration-150",
            "[&::-webkit-slider-thumb]:hover:bg-zinc-800",
            "[&::-moz-range-thumb]:h-5 [&::-moz-range-thumb]:w-5",
            "[&::-moz-range-thumb]:appearance-none [&::-moz-range-thumb]:rounded-full",
            "[&::-moz-range-thumb]:border-0 [&::-moz-range-thumb]:bg-zinc-900",
            "[&::-moz-range-thumb]:shadow [&::-moz-range-thumb]:transition-all",
            "[&::-moz-range-thumb]:duration-150 [&::-moz-range-thumb]:hover:bg-zinc-800",
            @class
          ])
        }
        {@rest}
      />
      <span :if={@show_value} class="mt-1 block text-center text-xs text-zinc-600">
        <%= @value %>
      </span>
    </div>
    """
  end
end
