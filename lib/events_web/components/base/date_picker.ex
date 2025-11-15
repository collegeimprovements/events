defmodule EventsWeb.Components.Base.DatePicker do
  @moduledoc """
  DatePicker component combining input and calendar.

  ## Examples

      <.date_picker name="date" placeholder="Pick a date" />
      <.date_picker name="start_date" value={~D[2024-01-01]} />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  import EventsWeb.Components.Base.Calendar
  alias Phoenix.LiveView.JS

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: "Pick a date"
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def date_picker(assigns) do
    assigns = assign_new(assigns, :id, fn -> "date-picker-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div class="relative w-full" id={@id}>
      <button
        type="button"
        phx-click={toggle_date_picker(@id)}
        disabled={@disabled}
        class={
          classes([
            "flex h-10 w-full items-center justify-between rounded-md border bg-white px-3 py-2",
            "text-sm text-zinc-900 placeholder:text-zinc-500",
            "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            if(@error, do: "border-red-500", else: "border-zinc-300"),
            @class
          ])
        }
      >
        <span class={if @value, do: "", else: "text-zinc-500"}>
          <%= if @value, do: format_date(@value), else: @placeholder %>
        </span>
        <svg
          class="h-4 w-4 opacity-50"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M6 2a1 1 0 00-1 1v1H4a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a1 1 0 10-2 0v1H7V3a1 1 0 00-1-1zm0 5a1 1 0 000 2h8a1 1 0 100-2H6z"
            clip-rule="evenodd"
          />
        </svg>
      </button>
      <div
        id={"#{@id}-calendar"}
        class="absolute z-50 mt-2 hidden"
      >
        <.calendar name={@name} value={@value} />
      </div>
      <p :if={@error} class="mt-1 text-xs text-red-600">
        <%= @error %>
      </p>
    </div>
    """
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")
  defp format_date(date) when is_binary(date), do: date

  defp toggle_date_picker(id) do
    JS.toggle(to: "##{id}-calendar", in: "fade-in-scale", out: "fade-out-scale")
  end
end
