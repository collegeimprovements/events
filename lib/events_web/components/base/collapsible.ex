defmodule EventsWeb.Components.Base.Collapsible do
  @moduledoc """
  Collapsible component for expandable content.

  ## Examples

      <.collapsible>
        <:trigger>
          <.button variant="ghost">Toggle</.button>
        </:trigger>
        <:content>
          <p>This content can be expanded and collapsed.</p>
        </:content>
      </.collapsible>

      <.collapsible open>
        <:trigger>Show Details</:trigger>
        <:content>Details content here</:content>
      </.collapsible>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :open, :boolean, default: false
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :trigger, required: true
  slot :content, required: true

  def collapsible(assigns) do
    assigns = assign_new(assigns, :id, fn -> "collapsible-#{:erlang.unique_integer([:positive])}" end)

    ~H"""
    <div class={classes([@class])} {@rest}>
      <div phx-click={toggle_collapsible(@id)} class="cursor-pointer">
        <%= render_slot(@trigger) %>
      </div>
      <div
        id={"#{@id}-content"}
        class={
          classes([
            "overflow-hidden transition-all duration-300",
            if(@open, do: "block", else: "hidden")
          ])
        }
      >
        <%= render_slot(@content) %>
      </div>
    </div>
    """
  end

  defp toggle_collapsible(id) do
    JS.toggle(
      to: "##{id}-content",
      in: {"ease-out duration-300", "opacity-0", "opacity-100"},
      out: {"ease-in duration-200", "opacity-100", "opacity-0"}
    )
  end
end
