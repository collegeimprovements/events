defmodule EventsWeb.Components.Base.RadioGroup do
  @moduledoc """
  RadioGroup component for single selection from multiple options.

  ## Examples

      <.radio_group name="plan">
        <:radio value="free" label="Free" />
        <:radio value="pro" label="Pro" checked />
        <:radio value="enterprise" label="Enterprise" />
      </.radio_group>

      <.radio_group name="size" orientation="horizontal">
        <:radio value="sm" label="Small" />
        <:radio value="md" label="Medium" />
        <:radio value="lg" label="Large" />
      </.radio_group>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  @orientation_map %{
    "horizontal" => "flex-row",
    "vertical" => "flex-col"
  }

  attr :name, :string, required: true
  attr :orientation, :string, default: "vertical", values: ~w(vertical horizontal)
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :radio, required: true do
    attr :value, :string, required: true
    attr :label, :string, required: true
    attr :checked, :boolean
    attr :disabled, :boolean
  end

  def radio_group(assigns) do
    ~H"""
    <div role="radiogroup" class={group_classes(@orientation, @class)} {@rest}>
      <%= for radio <- @radio do %>
        <div class="flex items-center gap-2">
          <input
            type="radio"
            id={"#{@name}-#{radio.value}"}
            name={@name}
            value={radio.value}
            checked={radio[:checked] || false}
            disabled={@disabled || radio[:disabled] || false}
            class={radio_classes()}
          />
          <label
            for={"#{@name}-#{radio.value}"}
            class="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
          >
            <%= radio.label %>
          </label>
        </div>
      <% end %>
    </div>
    """
  end

  defp group_classes(orientation, custom_class) do
    [
      "flex gap-4",
      Map.get(@orientation_map, orientation, @orientation_map["vertical"]),
      custom_class
    ]
    |> Utils.classes()
  end

  defp radio_classes do
    [
      "peer h-4 w-4 shrink-0 rounded-full border border-zinc-300",
      "bg-white text-zinc-900 transition-colors duration-150",
      "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50",
      "checked:bg-zinc-900 checked:border-zinc-900"
    ]
    |> Utils.classes()
  end
end
