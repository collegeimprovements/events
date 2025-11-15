defmodule EventsWeb.Components.Base.Combobox do
  @moduledoc """
  Combobox component for searchable select.

  ## Examples

      <.combobox name="language" placeholder="Select language...">
        <:option value="js">JavaScript</:option>
        <:option value="ts">TypeScript</:option>
        <:option value="ex">Elixir</:option>
        <:option value="py">Python</:option>
      </.combobox>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: "Search..."
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :option, required: true do
    attr :value, :string, required: true
  end

  def combobox(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> "combobox-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div class="relative w-full" id={@id} phx-hook="Combobox">
      <input type="hidden" name={@name} value={@value} />
      <button
        type="button"
        role="combobox"
        aria-expanded="false"
        aria-haspopup="listbox"
        disabled={@disabled}
        phx-click={toggle_combobox(@id)}
        class={
          classes([
            "flex h-10 w-full items-center justify-between rounded-md border bg-white px-3 py-2",
            "text-sm placeholder:text-zinc-500",
            "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            @class
          ])
        }
      >
        <span><%= selected_label(@option, @value) || @placeholder %></span>
        <svg
          class="ml-2 h-4 w-4 shrink-0 opacity-50"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M10 3a1 1 0 01.707.293l3 3a1 1 0 01-1.414 1.414L10 5.414 7.707 7.707a1 1 0 01-1.414-1.414l3-3A1 1 0 0110 3zm-3.707 9.293a1 1 0 011.414 0L10 14.586l2.293-2.293a1 1 0 011.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z"
            clip-rule="evenodd"
          />
        </svg>
      </button>
      <div
        id={"#{@id}-dropdown"}
        class="absolute z-50 mt-1 hidden w-full rounded-md border border-zinc-200 bg-white shadow-lg"
        role="listbox"
      >
        <div class="p-2">
          <input
            type="text"
            placeholder="Search..."
            class="flex h-9 w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm outline-none"
            phx-keyup="search-combobox"
            phx-target={@id}
          />
        </div>
        <div class="max-h-60 overflow-auto p-1">
          <%= for option <- @option do %>
            <div
              role="option"
              aria-selected={to_string(@value == option.value)}
              phx-click={select_combobox(@id, @name, option.value)}
              class={
                classes([
                  "cursor-pointer rounded-sm px-2 py-1.5 text-sm hover:bg-zinc-100",
                  if(@value == option.value, do: "bg-zinc-50 font-medium", else: "")
                ])
              }
            >
              <%= render_slot(option) %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp selected_label(options, value) do
    Enum.find_value(options, fn option ->
      if option.value == value,
        do: Phoenix.HTML.Safe.to_iodata(option.inner_block) |> IO.iodata_to_binary()
    end)
  end

  defp toggle_combobox(id) do
    JS.toggle(to: "##{id}-dropdown", in: "fade-in-scale", out: "fade-out-scale")
  end

  defp select_combobox(id, name, value) do
    JS.hide(to: "##{id}-dropdown")
    |> JS.set_attribute({"value", value}, to: "##{id} input[name='#{name}']")
  end
end
