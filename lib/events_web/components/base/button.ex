defmodule EventsWeb.Components.Base.Button do
  @moduledoc """
  Button component for user interactions.

  Supports multiple variants, sizes, and states.

  ## Examples

      <.button>Click me</.button>
      <.button variant="outline">Outline</.button>
      <.button variant="destructive" size="sm">Delete</.button>
      <.button variant="ghost" disabled>Disabled</.button>
      <.button variant="link" navigate={~p"/home"}>Home</.button>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

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
        classes([
          "inline-flex items-center justify-center gap-2",
          "rounded-md font-medium",
          "transition-colors duration-150",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2",
          "disabled:pointer-events-none disabled:opacity-50",
          "whitespace-nowrap",
          variant_classes(@variant),
          size_classes(@size),
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  defp variant_classes("default"),
    do: "bg-zinc-900 text-zinc-50 shadow hover:bg-zinc-800 focus-visible:ring-zinc-950"

  defp variant_classes("primary"),
    do: "bg-blue-600 text-white shadow hover:bg-blue-700 focus-visible:ring-blue-600"

  defp variant_classes("secondary"),
    do: "bg-zinc-100 text-zinc-900 shadow-sm hover:bg-zinc-200 focus-visible:ring-zinc-500"

  defp variant_classes("outline"),
    do:
      "border border-zinc-300 bg-white text-zinc-900 shadow-sm hover:bg-zinc-50 focus-visible:ring-zinc-500"

  defp variant_classes("ghost"),
    do: "text-zinc-900 hover:bg-zinc-100 focus-visible:ring-zinc-500"

  defp variant_classes("destructive"),
    do: "bg-red-600 text-white shadow hover:bg-red-700 focus-visible:ring-red-600"

  defp variant_classes("link"),
    do: "text-zinc-900 underline-offset-4 hover:underline"

  defp size_classes("default"), do: "h-10 px-4 py-2 text-sm"
  defp size_classes("sm"), do: "h-8 px-3 py-1 text-xs rounded"
  defp size_classes("lg"), do: "h-12 px-6 py-3 text-base"
  defp size_classes("icon"), do: "h-10 w-10 p-0"
  defp size_classes("icon-sm"), do: "h-8 w-8 p-0"
  defp size_classes("icon-lg"), do: "h-12 w-12 p-0"
end
