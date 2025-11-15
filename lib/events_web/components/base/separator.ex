defmodule EventsWeb.Components.Base.Separator do
  @moduledoc """
  Separator component for visually dividing content.

  ## Examples

      <.separator />
      <.separator orientation="vertical" />
      <.separator class="my-4" />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :orientation, :string, default: "horizontal", values: ~w(horizontal vertical)
  attr :class, :string, default: nil
  attr :rest, :global

  def separator(assigns) do
    ~H"""
    <div
      role="separator"
      aria-orientation={@orientation}
      class={
        classes([
          "bg-zinc-200 shrink-0",
          if(@orientation == "horizontal", do: "h-px w-full", else: "h-full w-px"),
          @class
        ])
      }
      {@rest}
    />
    """
  end
end
