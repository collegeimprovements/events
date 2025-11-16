defmodule EventsWeb.Components.Base.Toast do
  @moduledoc """
  Toast component for temporary notifications.

  ## Examples

      <.toast variant="default">
        <:title>Success</:title>
        <:description>Your changes have been saved.</:description>
      </.toast>

      <.toast variant="error" dismissible>
        <:title>Error</:title>
        <:description>Something went wrong.</:description>
      </.toast>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils
  alias Phoenix.LiveView.JS

  @variant_map %{
    "default" => "border-zinc-200 bg-white text-zinc-900",
    "success" => "border-green-200 bg-green-50 text-green-900",
    "error" => "border-red-200 bg-red-50 text-red-900",
    "warning" => "border-yellow-200 bg-yellow-50 text-yellow-900",
    "info" => "border-blue-200 bg-blue-50 text-blue-900"
  }

  attr :id, :string, default: nil
  attr :variant, :string, default: "default", values: ~w(default success error warning info)
  attr :dismissible, :boolean, default: true
  attr :duration, :integer, default: 5000
  attr :class, :string, default: nil
  attr :rest, :global

  slot :title
  slot :description
  slot :action

  def toast(assigns) do
    assigns = assign_new(assigns, :id, fn -> "toast-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div
      id={@id}
      role="alert"
      class={toast_classes(@variant, @class)}
      phx-hook="Toast"
      data-duration={@duration}
      {@rest}
    >
      <div class="flex-1 space-y-1">
        <h3 :if={@title != []} class="text-sm font-semibold">
          <%= render_slot(@title) %>
        </h3>
        <div :if={@description != []} class="text-sm opacity-90">
          <%= render_slot(@description) %>
        </div>
      </div>
      <div :if={@action != []} class="flex shrink-0 items-center gap-2">
        <%= render_slot(@action) %>
      </div>
      <button
        :if={@dismissible}
        type="button"
        phx-click={JS.hide(to: "##{@id}", transition: "fade-out")}
        class="shrink-0 rounded-md opacity-70 transition-opacity hover:opacity-100"
        aria-label="Close"
      >
        <svg
          class="h-4 w-4"
          xmlns="http://www.w3.org/2000/svg"
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
    """
  end

  defp toast_classes(variant, custom_class) do
    [
      "pointer-events-auto relative flex w-full max-w-md items-center",
      "justify-between space-x-4 overflow-hidden rounded-md border p-4",
      "shadow-lg transition-all animate-in slide-in-from-top-full",
      Map.get(@variant_map, variant, @variant_map["default"]),
      custom_class
    ]
    |> Utils.classes()
  end
end
