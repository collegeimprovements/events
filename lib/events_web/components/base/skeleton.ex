defmodule EventsWeb.Components.Base.Skeleton do
  @moduledoc """
  Skeleton component for loading placeholders.

  ## Examples

      <.skeleton class="h-4 w-48" />
      <.skeleton class="h-12 w-12 rounded-full" />
      <.skeleton variant="text" />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :variant, :string, default: "default", values: ~w(default text circle rectangular)
  attr :class, :string, default: nil
  attr :rest, :global

  def skeleton(assigns) do
    ~H"""
    <div
      class={
        classes([
          "animate-pulse bg-zinc-200",
          variant_classes(@variant),
          @class
        ])
      }
      {@rest}
    />
    """
  end

  defp variant_classes("default"), do: "rounded-md"
  defp variant_classes("text"), do: "h-4 w-full rounded"
  defp variant_classes("circle"), do: "rounded-full"
  defp variant_classes("rectangular"), do: "rounded-none"
end
