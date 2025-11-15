defmodule EventsWeb.Components.Base.Tabs do
  @moduledoc """
  Tabs component for organizing content into switchable panels.

  ## Examples

      <.tabs default_value="tab1">
        <:list>
          <:trigger value="tab1">Account</:trigger>
          <:trigger value="tab2">Password</:trigger>
          <:trigger value="tab3">Settings</:trigger>
        </:list>
        <:content value="tab1">
          Account settings content
        </:content>
        <:content value="tab2">
          Password settings content
        </:content>
        <:content value="tab3">
          General settings content
        </:content>
      </.tabs>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :default_value, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :list, required: true do
    slot :trigger do
      attr :value, :string, required: true
    end
  end

  slot :content, required: true do
    attr :value, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <div class={classes([@class])} {@rest}>
      <%= for list <- @list do %>
        <div class="inline-flex h-10 items-center justify-center rounded-md bg-zinc-100 p-1 text-zinc-500">
          <%= for trigger <- list[:trigger] || [] do %>
            <button
              type="button"
              role="tab"
              phx-click={switch_tab(trigger.value)}
              aria-selected={to_string(@default_value == trigger.value)}
              aria-controls={"tab-content-#{trigger.value}"}
              class={
                classes([
                  "inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5",
                  "text-sm font-medium ring-offset-white transition-all",
                  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-950 focus-visible:ring-offset-2",
                  "disabled:pointer-events-none disabled:opacity-50",
                  if(@default_value == trigger.value,
                    do: "bg-white text-zinc-900 shadow-sm",
                    else: "hover:bg-white/50 hover:text-zinc-900"
                  )
                ])
              }
            >
              <%= render_slot(trigger) %>
            </button>
          <% end %>
        </div>
      <% end %>
      <%= for content <- @content do %>
        <div
          id={"tab-content-#{content.value}"}
          role="tabpanel"
          tabindex="0"
          class={
            classes([
              "mt-2 ring-offset-white focus-visible:outline-none focus-visible:ring-2",
              "focus-visible:ring-zinc-950 focus-visible:ring-offset-2",
              if(@default_value == content.value, do: "block", else: "hidden")
            ])
          }
        >
          <%= render_slot(content) %>
        </div>
      <% end %>
    </div>
    """
  end

  defp switch_tab(value) do
    JS.hide(to: "[role='tabpanel']")
    |> JS.show(to: "#tab-content-#{value}")
    |> JS.remove_class("bg-white text-zinc-900 shadow-sm", to: "[role='tab']")
    |> JS.add_class("bg-white text-zinc-900 shadow-sm",
      to: "[aria-controls='tab-content-#{value}']"
    )
  end
end
