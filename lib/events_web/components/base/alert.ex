defmodule EventsWeb.Components.Base.Alert do
  @moduledoc """
  Alert component for displaying important messages.

  ## Examples

      <.alert>
        <:title>Heads up!</:title>
        <:description>This is an informational message.</:description>
      </.alert>

      <.alert variant="error">
        <:title>Error</:title>
        <:description>Something went wrong.</:description>
      </.alert>

      <.alert variant="success" dismissible>
        <:title>Success</:title>
        <:description>Your changes have been saved.</:description>
      </.alert>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :variant, :string,
    default: "default",
    values: ~w(default info success warning error)

  attr :dismissible, :boolean, default: false
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :icon
  slot :title
  slot :description

  def alert(assigns) do
    assigns = assign_new(assigns, :id, fn -> "alert-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div
      id={@id}
      role="alert"
      class={
        classes([
          "relative w-full rounded-lg border p-4",
          variant_classes(@variant),
          @class
        ])
      }
      {@rest}
    >
      <div class="flex gap-3">
        <div :if={@icon != []} class="shrink-0">
          <%= render_slot(@icon) %>
        </div>
        <div class="flex-1 space-y-1">
          <h5 :if={@title != []} class="font-medium leading-none tracking-tight">
            <%= render_slot(@title) %>
          </h5>
          <div :if={@description != []} class="text-sm opacity-90">
            <%= render_slot(@description) %>
          </div>
        </div>
        <button
          :if={@dismissible}
          type="button"
          phx-click={JS.hide(to: "##{@id}", transition: "fade-out")}
          class="shrink-0 rounded-md opacity-70 transition-opacity hover:opacity-100"
          aria-label="Close"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  defp variant_classes("default"),
    do: "border-zinc-200 bg-white text-zinc-900"

  defp variant_classes("info"),
    do: "border-blue-200 bg-blue-50 text-blue-900"

  defp variant_classes("success"),
    do: "border-green-200 bg-green-50 text-green-900"

  defp variant_classes("warning"),
    do: "border-yellow-200 bg-yellow-50 text-yellow-900"

  defp variant_classes("error"),
    do: "border-red-200 bg-red-50 text-red-900"
end
