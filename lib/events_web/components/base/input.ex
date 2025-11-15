defmodule EventsWeb.Components.Base.Input do
  @moduledoc """
  Input component for form text entry.

  ## Examples

      <.input type="text" name="email" placeholder="Enter email" />
      <.input type="password" name="password" required />
      <.input type="email" name="email" error="Invalid email" />
      <.input type="number" name="age" min="0" max="120" />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :type, :string, default: "text"
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols dirname inputmode list max maxlength min minlength
         multiple pattern readonly required rows spellcheck step)

  def input(assigns) do
    ~H"""
    <div class="w-full">
      <input
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        disabled={@disabled}
        aria-invalid={if @error, do: "true", else: "false"}
        aria-describedby={if @error, do: "#{@name}-error", else: nil}
        class={
          classes([
            "flex w-full rounded-md border bg-white px-3 py-2",
            "text-sm text-zinc-900 placeholder:text-zinc-500",
            "transition-colors duration-150",
            "focus:outline-none focus:ring-2 focus:ring-offset-2",
            "disabled:cursor-not-allowed disabled:opacity-50",
            if(@error,
              do: "border-red-500 focus:ring-red-500",
              else: "border-zinc-300 focus:ring-zinc-950"
            ),
            size_classes(@size),
            @class
          ])
        }
        {@rest}
      />
      <p :if={@error} id={"#{@name}-error"} class="mt-1 text-xs text-red-600">
        <%= @error %>
      </p>
    </div>
    """
  end

  defp size_classes("default"), do: "h-10"
  defp size_classes("sm"), do: "h-8 text-xs"
  defp size_classes("lg"), do: "h-12 text-base"
end
