defmodule EventsWeb.Components.Base.Sheet do
  @moduledoc """
  Sheet component for side panels.

  ## Examples

      <.sheet id="settings-sheet" side="right">
        <:trigger>
          <.button>Settings</.button>
        </:trigger>
        <:header>
          <:title>Settings</:title>
          <:description>Manage your preferences</:description>
        </:header>
        <:content>
          Settings content here
        </:content>
      </.sheet>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :side, :string, default: "right", values: ~w(left right top bottom)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger
  slot :header do
    slot :title
    slot :description
  end

  slot :content
  slot :footer

  def sheet(assigns) do
    ~H"""
    <div>
      <div :if={@trigger != []} phx-click={show_sheet(@id)}>
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={@id}
        class={
          classes([
            "fixed inset-0 z-50 bg-black/50",
            if(@open, do: "block", else: "hidden")
          ])
        }
        phx-click={hide_sheet(@id)}
        {@rest}
      >
        <div
          class={
            classes([
              "fixed bg-white shadow-lg",
              "animate-in slide-in-from-#{@side}",
              side_classes(@side),
              @class
            ])
          }
          phx-click="stop-propagation"
        >
          <button
            type="button"
            phx-click={hide_sheet(@id)}
            class="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-white transition-opacity hover:opacity-100"
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
          <div :if={@header != []} class="flex flex-col space-y-2 p-6">
            <%= for header <- @header do %>
              <h2 :if={header[:title] != []} class="text-lg font-semibold">
                <%= render_slot(header, :title) %>
              </h2>
              <p :if={header[:description] != []} class="text-sm text-zinc-500">
                <%= render_slot(header, :description) %>
              </p>
            <% end %>
          </div>
          <div :if={@content != []} class="p-6 pt-0">
            <%= render_slot(@content) %>
          </div>
          <div :if={@footer != []} class="border-t border-zinc-200 p-6">
            <%= render_slot(@footer) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp side_classes("left"), do: "inset-y-0 left-0 h-full w-3/4 sm:max-w-sm"
  defp side_classes("right"), do: "inset-y-0 right-0 h-full w-3/4 sm:max-w-sm"
  defp side_classes("top"), do: "inset-x-0 top-0 h-auto max-h-[80vh]"
  defp side_classes("bottom"), do: "inset-x-0 bottom-0 h-auto max-h-[80vh]"

  def show_sheet(id) do
    JS.show(to: "##{id}", transition: {"ease-out duration-300", "opacity-0", "opacity-100"})
  end

  def hide_sheet(id) do
    JS.hide(to: "##{id}", transition: {"ease-in duration-200", "opacity-100", "opacity-0"})
  end
end
