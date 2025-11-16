defmodule EventsWeb.Components.Base.Skeleton do
  @moduledoc """
  Skeleton component for loading placeholders.

  ## Examples

      <.skeleton class="h-4 w-48" />
      <.skeleton class="h-12 w-12 rounded-full" />
      <.skeleton variant="text" />
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  @variant_map %{
    "default" => "rounded-md",
    "text" => "h-4 w-full rounded",
    "circle" => "rounded-full",
    "rectangular" => "rounded-none"
  }

  attr :variant, :string, default: "default", values: ~w(default text circle rectangular)
  attr :class, :string, default: nil
  attr :rest, :global

  def skeleton(assigns) do
    ~H"""
    <div class={skeleton_classes(@variant, @class)} {@rest} />
    """
  end

  defp skeleton_classes(variant, custom_class) do
    [
      "animate-pulse bg-zinc-200",
      Map.get(@variant_map, variant, @variant_map["default"]),
      custom_class
    ]
    |> Utils.classes()
  end
end
