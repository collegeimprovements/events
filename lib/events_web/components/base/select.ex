defmodule EventsWeb.Components.Base.Select do
  @moduledoc """
  Select component with custom styling (requires JavaScript hook).

  ## Examples

      <.select name="country" placeholder="Select country">
        <:option value="us">United States</:option>
        <:option value="uk">United Kingdom</:option>
        <:option value="ca">Canada</:option>
      </.select>

      <.select name="priority" value="high">
        <:option value="low">Low</:option>
        <:option value="medium">Medium</:option>
        <:option value="high">High</:option>
      </.select>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils
  alias Phoenix.LiveView.JS

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: "Select..."
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :option, required: true do
    attr :value, :string, required: true
  end

  def select(assigns) do
    assigns = assign_new(assigns, :id, fn -> "select-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div class="relative w-full" id={@id} phx-hook="Select">
      <input type="hidden" name={@name} value={@value} />
      <button
        type="button"
        role="combobox"
        aria-expanded="false"
        aria-haspopup="listbox"
        disabled={@disabled}
        phx-click={toggle_dropdown(@id)}
        class={button_classes(@error, @class)}
      >
        <span class={placeholder_classes(@value)}>
          <%= selected_label(@option, @value) || @placeholder %>
        </span>
        <svg
          class="h-4 w-4 opacity-50"
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
      <div
        id={"#{@id}-dropdown"}
        class="absolute z-50 mt-1 hidden w-full rounded-md border border-zinc-200 bg-white shadow-lg"
        role="listbox"
      >
        <%= for option <- @option do %>
          <div
            role="option"
            aria-selected={to_string(@value == option.value)}
            phx-click={select_option(@id, @name, option.value)}
            class={option_classes(@value == option.value)}
          >
            <%= render_slot(option) %>
          </div>
        <% end %>
      </div>
      <p :if={@error} class="mt-1 text-xs text-red-600">
        <%= @error %>
      </p>
    </div>
    """
  end

  defp button_classes(error, custom_class) do
    [
      "flex h-10 w-full items-center justify-between rounded-md border bg-white px-3 py-2",
      "text-sm text-zinc-900 transition-colors duration-150",
      "focus:outline-none focus:ring-2 focus:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50",
      error && "border-red-500 focus:ring-red-500" || "border-zinc-300 focus:ring-zinc-950",
      custom_class
    ]
    |> Utils.classes()
  end

  defp placeholder_classes(value), do: value && "" || "text-zinc-500"

  defp option_classes(selected) do
    [
      "cursor-pointer px-3 py-2 text-sm hover:bg-zinc-100",
      selected && "bg-zinc-50 font-medium"
    ]
    |> Utils.classes()
  end

  defp selected_label(options, value) do
    options
    |> Enum.find_value(fn option ->
      option.value == value && Phoenix.HTML.Safe.to_iodata(option.inner_block) |> IO.iodata_to_binary()
    end)
  end

  defp toggle_dropdown(id) do
    JS.toggle(to: "##{id}-dropdown", in: "fade-in-scale", out: "fade-out-scale")
  end

  defp select_option(id, name, value) do
    JS.hide(to: "##{id}-dropdown")
    |> JS.set_attribute({"value", value}, to: "##{id} input[name='#{name}']")
  end
end
