defmodule EventsWeb.Components.Base.Label do
  @moduledoc """
  Label component for form inputs.

  ## Examples

      <.label for="email">Email</.label>
      <.label for="password" required>Password</.label>
      <.label class="text-lg">Custom Label</.label>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :for, :string, default: nil
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label
      for={@for}
      class={
        classes([
          "text-sm font-medium leading-none text-zinc-900",
          "peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
          @class
        ])
      }
      {@rest}
    >
      <%= render_slot(@inner_block) %>
      <span :if={@required} class="text-red-600" aria-label="required">*</span>
    </label>
    """
  end
end
