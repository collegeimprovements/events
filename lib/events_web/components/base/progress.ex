defmodule EventsWeb.Components.Base.Progress do
  @moduledoc """
  Progress component for displaying task completion.

  ## Examples

      <.progress value={50} />
      <.progress value={75} variant="success" />
      <.progress value={100} show_label />
      <.progress value={33} class="h-2" />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :value, :integer, required: true
  attr :max, :integer, default: 100
  attr :variant, :string, default: "default", values: ~w(default success warning error)
  attr :show_label, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def progress(assigns) do
    assigns = assign(assigns, :percentage, calculate_percentage(assigns.value, assigns.max))

    ~H"""
    <div
      role="progressbar"
      aria-valuenow={@value}
      aria-valuemin="0"
      aria-valuemax={@max}
      aria-label="Progress"
      class={classes(["relative", @class])}
      {@rest}
    >
      <div class="h-2 w-full overflow-hidden rounded-full bg-zinc-200">
        <div
          class={
            classes([
              "h-full transition-all duration-300 ease-in-out",
              variant_classes(@variant)
            ])
          }
          style={"width: #{@percentage}%"}
        />
      </div>
      <span :if={@show_label} class="mt-1 block text-xs text-zinc-600">
        <%= @percentage %>%
      </span>
    </div>
    """
  end

  defp calculate_percentage(value, max) when max > 0 do
    min(round(value / max * 100), 100)
  end

  defp calculate_percentage(_, _), do: 0

  defp variant_classes("default"), do: "bg-zinc-900"
  defp variant_classes("success"), do: "bg-green-600"
  defp variant_classes("warning"), do: "bg-yellow-600"
  defp variant_classes("error"), do: "bg-red-600"
end
