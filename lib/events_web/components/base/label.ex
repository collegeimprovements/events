defmodule EventsWeb.Components.Base.Label do
  @moduledoc """
  Label component for form inputs.

  ## Examples

      <.label for="email">Email</.label>
      <.label for="password" required>Password</.label>
      <.label class="text-lg">Custom Label</.label>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  attr :for, :string, default: nil
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class={label_classes(@class)} {@rest}>
      <%= render_slot(@inner_block) %>
      <span :if={@required} class="text-red-600" aria-label="required">*</span>
    </label>
    """
  end

  defp label_classes(custom_class) do
    [
      "text-sm font-medium leading-none text-zinc-900",
      "peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
      custom_class
    ]
    |> Utils.classes()
  end
end
