defmodule EventsWeb.Components.Base.AlertDialog do
  @moduledoc """
  AlertDialog component for important confirmations.

  ## Examples

      <.alert_dialog id="delete-confirm">
        <:trigger>
          <.button variant="destructive">Delete</.button>
        </:trigger>
        <:title>Are you absolutely sure?</:title>
        <:description>
          This action cannot be undone. This will permanently delete your account.
        </:description>
        <:action>
          <.button variant="outline" phx-click={hide_alert_dialog("delete-confirm")}>
            Cancel
          </.button>
          <.button variant="destructive">Delete</.button>
        </:action>
      </.alert_dialog>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger
  slot :title
  slot :description
  slot :action

  def alert_dialog(assigns) do
    ~H"""
    <div>
      <div :if={@trigger != []} phx-click={show_alert_dialog(@id)}>
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={@id}
        role="alertdialog"
        aria-modal="true"
        class={
          classes([
            "fixed inset-0 z-50 flex items-center justify-center bg-black/50",
            if(@open, do: "block", else: "hidden")
          ])
        }
        {@rest}
      >
        <div
          class={
            classes([
              "relative w-full max-w-lg rounded-lg border border-zinc-200 bg-white p-6 shadow-lg",
              "animate-in fade-in-0 zoom-in-95",
              @class
            ])
          }
        >
          <div class="flex flex-col space-y-2 text-center sm:text-left">
            <h2 :if={@title != []} class="text-lg font-semibold">
              <%= render_slot(@title) %>
            </h2>
            <p :if={@description != []} class="text-sm text-zinc-500">
              <%= render_slot(@description) %>
            </p>
          </div>
          <div :if={@action != []} class="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <%= render_slot(@action) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_alert_dialog(id) do
    JS.show(to: "##{id}", transition: {"ease-out duration-300", "opacity-0", "opacity-100"})
  end

  def hide_alert_dialog(id) do
    JS.hide(to: "##{id}", transition: {"ease-in duration-200", "opacity-100", "opacity-0"})
  end
end
