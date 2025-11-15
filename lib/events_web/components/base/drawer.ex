defmodule EventsWeb.Components.Base.Drawer do
  @moduledoc """
  Drawer component (alias for Sheet with specific styling).

  ## Examples

      <.drawer id="nav-drawer">
        <:trigger>
          <.button variant="ghost">Menu</.button>
        </:trigger>
        <:content>
          Navigation items
        </:content>
      </.drawer>
  """
  use Phoenix.Component
  defdelegate drawer(assigns), to: EventsWeb.Components.Base.Sheet, as: :sheet
end
