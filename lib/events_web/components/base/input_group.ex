defmodule EventsWeb.Components.Base.InputGroup do
  @moduledoc """
  InputGroup component for inputs with additional decorations.

  ## Examples

      <.input_group>
        <:prefix>$</:prefix>
        <.input type="number" name="amount" />
      </.input_group>

      <.input_group>
        <.input type="text" name="email" />
        <:suffix>@example.com</:suffix>
      </.input_group>

      <.input_group>
        <:prefix>https://</:prefix>
        <.input type="text" name="domain" />
        <:suffix>.com</:suffix>
      </.input_group>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :class, :string, default: nil
  attr :rest, :global

  slot :prefix
  slot :inner_block, required: true
  slot :suffix

  def input_group(assigns) do
    ~H"""
    <div
      class={
        classes([
          "flex w-full items-center overflow-hidden rounded-md border border-zinc-300",
          "focus-within:ring-2 focus-within:ring-zinc-950 focus-within:ring-offset-2",
          @class
        ])
      }
      {@rest}
    >
      <span
        :if={@prefix != []}
        class="flex items-center border-r border-zinc-300 bg-zinc-50 px-3 text-sm text-zinc-500"
      >
        <%= render_slot(@prefix) %>
      </span>
      <div class="flex-1 [&>input]:border-0 [&>input]:ring-0 [&>input]:focus:ring-0">
        <%= render_slot(@inner_block) %>
      </div>
      <span
        :if={@suffix != []}
        class="flex items-center border-l border-zinc-300 bg-zinc-50 px-3 text-sm text-zinc-500"
      >
        <%= render_slot(@suffix) %>
      </span>
    </div>
    """
  end
end
