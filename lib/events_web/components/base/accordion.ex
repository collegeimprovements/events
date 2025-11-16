defmodule EventsWeb.Components.Base.Accordion do
  @moduledoc """
  Accordion component for collapsible content sections.

  ## Examples

      <.accordion>
        <:item title="Section 1" value="1">
          Content for section 1
        </:item>
        <:item title="Section 2" value="2" open>
          Content for section 2
        </:item>
        <:item title="Section 3" value="3">
          Content for section 3
        </:item>
      </.accordion>

      <.accordion type="multiple">
        <:item title="Item 1" value="1">Content 1</:item>
        <:item title="Item 2" value="2">Content 2</:item>
      </.accordion>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils
  alias Phoenix.LiveView.JS

  attr :type, :string, default: "single", values: ~w(single multiple)
  attr :collapsible, :boolean, default: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :item, required: true do
    attr :title, :string, required: true
    attr :value, :string, required: true
    attr :open, :boolean
  end

  def accordion(assigns) do
    ~H"""
    <div class={container_classes(@class)} {@rest}>
      <%= for item <- @item do %>
        <div class="group" data-state={item_state(item[:open])}>
          <h3 class="flex">
            <button
              type="button"
              phx-click={toggle_accordion(item.value)}
              class={trigger_classes()}
              aria-expanded={to_string(item[:open] || false)}
              aria-controls={"accordion-content-#{item.value}"}
            >
              <span><%= item.title %></span>
              <svg
                class={icon_classes(item[:open])}
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
          </h3>
          <div
            id={"accordion-content-#{item.value}"}
            role="region"
            aria-labelledby={"accordion-trigger-#{item.value}"}
            class={content_classes(item[:open])}
          >
            <div class="px-4 pb-4 pt-0">
              <%= render_slot(item) %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp container_classes(custom_class) do
    ["divide-y divide-zinc-200 rounded-md border border-zinc-200", custom_class]
    |> Utils.classes()
  end

  defp trigger_classes do
    [
      "flex flex-1 items-center justify-between py-4 px-4",
      "font-medium transition-all hover:underline text-left"
    ]
    |> Utils.classes()
  end

  defp icon_classes(open) do
    [
      "h-4 w-4 shrink-0 transition-transform duration-200",
      open && "rotate-180"
    ]
    |> Utils.classes()
  end

  defp content_classes(open) do
    [
      "overflow-hidden transition-all",
      open && "block" || "hidden"
    ]
    |> Utils.classes()
  end

  defp item_state(true), do: "open"
  defp item_state(_), do: "closed"

  defp toggle_accordion(value) do
    JS.toggle(to: "#accordion-content-#{value}")
    |> JS.toggle_class("rotate-180", to: "#accordion-content-#{value} ~ h3 button svg")
  end
end
