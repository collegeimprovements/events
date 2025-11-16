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
  alias EventsWeb.Components.Base.Utils

  @size_map %{
    "sm" => "h-3 w-3",
    "default" => "h-4 w-4",
    "lg" => "h-5 w-5"
  }

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
        class={checkbox_classes(@size, @class)}
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

  defp checkbox_classes(size, custom_class) do
    [
      "peer shrink-0 rounded border border-zinc-300",
      "bg-white text-zinc-900",
      "transition-colors duration-150",
      "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50",
      "checked:bg-zinc-900 checked:border-zinc-900",
      Map.get(@size_map, size, @size_map["default"]),
      custom_class
    ]
    |> Utils.classes()
  end
end
