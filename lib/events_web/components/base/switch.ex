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
  import EventsWeb.Components.Base, only: [classes: 1]

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
        class={
          classes([
            "peer inline-flex shrink-0 cursor-pointer rounded-full",
            "border-2 border-transparent transition-colors",
            "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            if(@checked, do: "bg-zinc-900", else: "bg-zinc-200"),
            size_classes(@size),
            @class
          ])
        }
      >
        <span
          class={
            classes([
              "pointer-events-none block rounded-full bg-white shadow-lg",
              "ring-0 transition-transform",
              thumb_size(@size),
              if(@checked, do: thumb_translate(@size), else: "translate-x-0")
            ])
          }
        />
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

  defp size_classes("default"), do: "h-6 w-11"
  defp size_classes("sm"), do: "h-5 w-9"
  defp size_classes("lg"), do: "h-7 w-14"

  defp thumb_size("default"), do: "h-5 w-5"
  defp thumb_size("sm"), do: "h-4 w-4"
  defp thumb_size("lg"), do: "h-6 w-6"

  defp thumb_translate("default"), do: "translate-x-5"
  defp thumb_translate("sm"), do: "translate-x-4"
  defp thumb_translate("lg"), do: "translate-x-7"
end
