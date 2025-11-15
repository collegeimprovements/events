defmodule EventsWeb.Components.Base.NativeSelect do
  @moduledoc """
  NativeSelect component using native HTML select element.

  ## Examples

      <.native_select name="country">
        <:option value="">Select a country</:option>
        <:option value="us">United States</:option>
        <:option value="uk">United Kingdom</:option>
      </.native_select>

      <.native_select name="status" error="Status is required">
        <:option value="active">Active</:option>
        <:option value="inactive">Inactive</:option>
      </.native_select>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(multiple required form autocomplete)

  slot :option, required: true do
    attr :value, :string, required: true
    attr :selected, :boolean
    attr :disabled, :boolean
  end

  def native_select(assigns) do
    ~H"""
    <div class="w-full">
      <select
        name={@name}
        disabled={@disabled}
        aria-invalid={if @error, do: "true", else: "false"}
        aria-describedby={if @error, do: "#{@name}-error", else: nil}
        class={
          classes([
            "flex h-10 w-full rounded-md border bg-white px-3 py-2",
            "text-sm text-zinc-900",
            "transition-colors duration-150",
            "focus:outline-none focus:ring-2 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            if(@error,
              do: "border-red-500 focus:ring-red-500",
              else: "border-zinc-300 focus:ring-zinc-950"
            ),
            @class
          ])
        }
        {@rest}
      >
        <option :if={@placeholder} value="" disabled selected={is_nil(@value)}>
          <%= @placeholder %>
        </option>
        <%= for option <- @option do %>
          <option
            value={option.value}
            selected={option[:selected] || @value == option.value}
            disabled={option[:disabled] || false}
          >
            <%= render_slot(option) %>
          </option>
        <% end %>
      </select>
      <p :if={@error} id={"#{@name}-error"} class="mt-1 text-xs text-red-600">
        <%= @error %>
      </p>
    </div>
    """
  end
end
