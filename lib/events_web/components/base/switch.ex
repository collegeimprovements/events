defmodule EventsWeb.Components.Base.Switch do
  @moduledoc """
  Switch component for toggle controls.

  ## Examples

      <.switch name="notifications" />
      <.switch name="dark_mode" checked />
      <.switch name="marketing" label="Marketing emails" />
      <.switch name="feature" disabled />
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  @size_map %{
    "sm" => %{container: "h-5 w-9", thumb: "h-4 w-4", translate: "translate-x-4"},
    "default" => %{container: "h-6 w-11", thumb: "h-5 w-5", translate: "translate-x-5"},
    "lg" => %{container: "h-7 w-14", thumb: "h-6 w-6", translate: "translate-x-7"}
  }

  attr :name, :string, required: true
  attr :checked, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :label, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-* form)

  def switch(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <button
        type="button"
        role="switch"
        id={@name}
        name={@name}
        aria-checked={to_string(@checked)}
        disabled={@disabled}
        phx-click={@rest[:"phx-click"]}
        phx-value-name={@name}
        class={switch_classes(@checked, @size, @class)}
      >
        <span class={thumb_classes(@checked, @size)} />
      </button>
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

  defp switch_classes(checked, size, custom_class) do
    size_config = Map.get(@size_map, size, @size_map["default"])

    [
      "peer inline-flex shrink-0 cursor-pointer rounded-full",
      "border-2 border-transparent transition-colors",
      "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50",
      checked && "bg-zinc-900" || "bg-zinc-200",
      size_config.container,
      custom_class
    ]
    |> Utils.classes()
  end

  defp thumb_classes(checked, size) do
    size_config = Map.get(@size_map, size, @size_map["default"])

    [
      "pointer-events-none block rounded-full bg-white shadow-lg",
      "ring-0 transition-transform",
      size_config.thumb,
      checked && size_config.translate || "translate-x-0"
    ]
    |> Utils.classes()
  end
end
