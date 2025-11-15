defmodule EventsWeb.Components.Base.Calendar do
  @moduledoc """
  Calendar component for date selection.

  ## Examples

      <.calendar name="date" />
      <.calendar name="birthdate" value={~D[2000-01-01]} />
      <.calendar name="event_date" min={Date.utc_today()} />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :min, :any, default: nil
  attr :max, :any, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def calendar(assigns) do
    assigns = assign(assigns, :current_date, assigns.value || Date.utc_today())

    ~H"""
    <div
      class={
        classes([
          "rounded-md border border-zinc-200 bg-white p-3",
          @class
        ])
      }
      phx-hook="Calendar"
      {@rest}
    >
      <div class="flex items-center justify-between mb-4">
        <button
          type="button"
          phx-click="prev-month"
          phx-target={@name}
          class="inline-flex items-center justify-center rounded-md p-2 hover:bg-zinc-100"
        >
          <svg
            class="h-4 w-4"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
        <div class="text-sm font-medium">
          <%= Calendar.strftime(@current_date, "%B %Y") %>
        </div>
        <button
          type="button"
          phx-click="next-month"
          phx-target={@name}
          class="inline-flex items-center justify-center rounded-md p-2 hover:bg-zinc-100"
        >
          <svg
            class="h-4 w-4"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
      </div>
      <div class="grid grid-cols-7 gap-1 text-center text-sm">
        <div class="text-zinc-500 font-medium text-xs">Su</div>
        <div class="text-zinc-500 font-medium text-xs">Mo</div>
        <div class="text-zinc-500 font-medium text-xs">Tu</div>
        <div class="text-zinc-500 font-medium text-xs">We</div>
        <div class="text-zinc-500 font-medium text-xs">Th</div>
        <div class="text-zinc-500 font-medium text-xs">Fr</div>
        <div class="text-zinc-500 font-medium text-xs">Sa</div>
        <%= for _day <- 1..35 do %>
          <button
            type="button"
            class={
              classes([
                "h-9 w-9 rounded-md text-sm hover:bg-zinc-100",
                "focus:bg-zinc-100 focus:outline-none"
              ])
            }
          >

          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
