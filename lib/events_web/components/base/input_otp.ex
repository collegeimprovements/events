defmodule EventsWeb.Components.Base.InputOTP do
  @moduledoc """
  InputOTP component for one-time password entry.

  ## Examples

      <.input_otp name="code" length={6} />
      <.input_otp name="pin" length={4} type="password" />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :name, :string, required: true
  attr :length, :integer, default: 6
  attr :type, :string, default: "text", values: ~w(text password)
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def input_otp(assigns) do
    ~H"""
    <div
      class={classes(["flex gap-2", @class])}
      phx-hook="InputOTP"
      id={"#{@name}-otp"}
      {@rest}
    >
      <%= for index <- 0..(@length - 1) do %>
        <input
          type={@type}
          name={"#{@name}[#{index}]"}
          maxlength="1"
          disabled={@disabled}
          class={
            classes([
              "h-12 w-12 rounded-md border border-zinc-300 bg-white",
              "text-center text-lg font-medium text-zinc-900",
              "transition-colors duration-150",
              "focus:border-zinc-900 focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
              "disabled:cursor-not-allowed disabled:opacity-50"
            ])
          }
        />
      <% end %>
    </div>
    """
  end
end
