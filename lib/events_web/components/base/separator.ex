defmodule EventsWeb.Components.Base.Separator do
  @moduledoc """
  Separator component for visually dividing content.

  ## Examples

      <.separator />
      <.separator orientation="vertical" />
      <.separator class="my-4" />
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  @orientation_map %{
    "horizontal" => "h-px w-full",
    "vertical" => "h-full w-px"
  }

  attr :orientation, :string, default: "horizontal", values: ~w(horizontal vertical)
  attr :class, :string, default: nil
  attr :rest, :global

  def separator(assigns) do
    ~H"""
    <div
      role="separator"
      aria-orientation={@orientation}
      class={separator_classes(@orientation, @class)}
      {@rest}
    />
    """
  end

  defp separator_classes(orientation, custom_class) do
    [
      "bg-zinc-200 shrink-0",
      Map.get(@orientation_map, orientation, @orientation_map["horizontal"]),
      custom_class
    ]
    |> Utils.classes()
  end
end
