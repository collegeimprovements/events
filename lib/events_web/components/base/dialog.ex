defmodule EventsWeb.Components.Base.Dialog do
  @moduledoc """
  Dialog component for modal windows.

  ## Examples

      <.dialog id="confirm-dialog">
        <:trigger>
          <.button>Open Dialog</.button>
        </:trigger>
        <:content>
          <:header>
            <:title>Confirm Action</:title>
            <:description>Are you sure you want to proceed?</:description>
          </:header>
          <:body>
            This action cannot be undone.
          </:body>
          <:footer>
            <.button variant="outline" phx-click={hide_dialog("confirm-dialog")}>
              Cancel
            </.button>
            <.button>Confirm</.button>
          </:footer>
        </:content>
      </.dialog>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger
  slot :content, required: true do
    slot :header do
      slot :title
      slot :description
    end

    slot :body
    slot :footer
  end

  def dialog(assigns) do
    ~H"""
    <div>
      <div :if={@trigger != []} phx-click={show_dialog(@id)}>
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={@id}
        class={
          classes([
            "fixed inset-0 z-50 flex items-center justify-center bg-black/50",
            if(@open, do: "block", else: "hidden")
          ])
        }
        phx-click={hide_dialog(@id)}
        {@rest}
      >
        <div
          class={
            classes([
              "relative w-full max-w-lg rounded-lg border border-zinc-200 bg-white shadow-lg",
              "animate-in fade-in-0 zoom-in-95",
              @class
            ])
          }
          phx-click="stop-propagation"
        >
          <button
            type="button"
            phx-click={hide_dialog(@id)}
            class="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-white transition-opacity hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2"
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
          <%= for content <- @content do %>
            <div :if={content[:header] != []} class="flex flex-col space-y-1.5 p-6 text-center sm:text-left">
              <%= for header <- content[:header] do %>
                <h2 :if={header[:title] != []} class="text-lg font-semibold leading-none tracking-tight">
                  <%= render_slot(header, :title) %>
                </h2>
                <p :if={header[:description] != []} class="text-sm text-zinc-500">
                  <%= render_slot(header, :description) %>
                </p>
              <% end %>
            </div>
            <div :if={content[:body] != []} class="p-6 pt-0">
              <%= render_slot(content, :body) %>
            </div>
            <div :if={content[:footer] != []} class="flex flex-col-reverse gap-2 p-6 pt-0 sm:flex-row sm:justify-end">
              <%= render_slot(content, :footer) %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def show_dialog(id) do
    JS.show(to: "##{id}", transition: {"ease-out duration-300", "opacity-0", "opacity-100"})
  end

  def hide_dialog(id) do
    JS.hide(to: "##{id}", transition: {"ease-in duration-200", "opacity-100", "opacity-0"})
  end
end
