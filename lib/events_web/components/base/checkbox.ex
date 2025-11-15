defmodule EventsWeb.Components.Base.Checkbox do
  @moduledoc """
  Checkbox component for boolean selections.

  ## Examples

      <.checkbox name="agree" />
      <.checkbox name="subscribe" checked />
      <.checkbox name="terms" label="I agree to terms" />
      <.checkbox name="newsletter" disabled />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :name, :string, required: true
  attr :checked, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :label, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(value form required)

  def checkbox(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <input
        type="checkbox"
        id={@name}
        name={@name}
        checked={@checked}
        disabled={@disabled}
        class={
          classes([
            "peer shrink-0 rounded border border-zinc-300",
            "bg-white text-zinc-900",
            "transition-colors duration-150",
            "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "checked:bg-zinc-900 checked:border-zinc-900",
            size_classes(@size),
            @class
          ])
        }
        {@rest}
      />
      <label
        :if={@label}
        for={@name}
        class="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
      >
        <%= @label %>
      </label>
    </div>
    """
  end

  defp size_classes("default"), do: "h-4 w-4"
  defp size_classes("sm"), do: "h-3 w-3"
  defp size_classes("lg"), do: "h-5 w-5"
end
