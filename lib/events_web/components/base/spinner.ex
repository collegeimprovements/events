defmodule EventsWeb.Components.Base.Spinner do
  @moduledoc """
  Spinner component for loading states.

  ## Examples

      <.spinner />
      <.spinner size="sm" />
      <.spinner size="lg" />
      <.spinner class="text-blue-600" />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :size, :string, default: "default", values: ~w(default sm lg xl)
  attr :class, :string, default: nil
  attr :rest, :global

  def spinner(assigns) do
    ~H"""
    <div
      role="status"
      aria-live="polite"
      aria-label="Loading"
      class={
        classes([
          "inline-block animate-spin rounded-full border-2 border-solid border-current border-r-transparent",
          "motion-reduce:animate-[spin_1.5s_linear_infinite]",
          size_classes(@size),
          @class
        ])
      }
      {@rest}
    >
      <span class="sr-only">Loading...</span>
    </div>
    """
  end

  defp size_classes("default"), do: "h-6 w-6"
  defp size_classes("sm"), do: "h-4 w-4 border"
  defp size_classes("lg"), do: "h-8 w-8"
  defp size_classes("xl"), do: "h-12 w-12 border-4"
end
