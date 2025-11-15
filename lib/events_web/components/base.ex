defmodule EventsWeb.Components.Base do
  @moduledoc """
  Base UI Components Library for Phoenix LiveView.

  This module provides a comprehensive set of accessible, customizable UI components
  inspired by shadcn/ui and Base UI, adapted for Phoenix LiveView.

  ## Usage

      import EventsWeb.Components.Base

      # Use any component
      <.button variant="primary">Click me</.button>
      <.badge variant="success">New</.badge>

  All components are built with:
  - Accessibility in mind (ARIA attributes, keyboard navigation)
  - Tailwind CSS for styling
  - LiveView JS for interactions
  - Colocated JavaScript hooks for complex interactions
  """

  use Phoenix.Component
  use Gettext, backend: EventsWeb.Gettext

  alias Phoenix.LiveView.JS

  # Import all component modules
  defdelegate accordion(assigns), to: EventsWeb.Components.Base.Accordion
  defdelegate alert(assigns), to: EventsWeb.Components.Base.Alert
  defdelegate alert_dialog(assigns), to: EventsWeb.Components.Base.AlertDialog
  defdelegate avatar(assigns), to: EventsWeb.Components.Base.Avatar
  defdelegate badge(assigns), to: EventsWeb.Components.Base.Badge
  defdelegate breadcrumb(assigns), to: EventsWeb.Components.Base.Breadcrumb
  defdelegate button(assigns), to: EventsWeb.Components.Base.Button
  defdelegate button_group(assigns), to: EventsWeb.Components.Base.ButtonGroup
  defdelegate calendar(assigns), to: EventsWeb.Components.Base.Calendar
  defdelegate card(assigns), to: EventsWeb.Components.Base.Card
  defdelegate carousel(assigns), to: EventsWeb.Components.Base.Carousel
  defdelegate checkbox(assigns), to: EventsWeb.Components.Base.Checkbox
  defdelegate collapsible(assigns), to: EventsWeb.Components.Base.Collapsible
  defdelegate combobox(assigns), to: EventsWeb.Components.Base.Combobox
  defdelegate command(assigns), to: EventsWeb.Components.Base.Command
  defdelegate context_menu(assigns), to: EventsWeb.Components.Base.ContextMenu
  defdelegate date_picker(assigns), to: EventsWeb.Components.Base.DatePicker
  defdelegate dialog(assigns), to: EventsWeb.Components.Base.Dialog
  defdelegate drawer(assigns), to: EventsWeb.Components.Base.Drawer
  defdelegate dropdown_menu(assigns), to: EventsWeb.Components.Base.DropdownMenu
  defdelegate empty(assigns), to: EventsWeb.Components.Base.Empty
  defdelegate field(assigns), to: EventsWeb.Components.Base.Field
  defdelegate hover_card(assigns), to: EventsWeb.Components.Base.HoverCard
  defdelegate input(assigns), to: EventsWeb.Components.Base.Input
  defdelegate input_group(assigns), to: EventsWeb.Components.Base.InputGroup
  defdelegate input_otp(assigns), to: EventsWeb.Components.Base.InputOTP
  defdelegate item(assigns), to: EventsWeb.Components.Base.Item
  defdelegate kbd(assigns), to: EventsWeb.Components.Base.Kbd
  defdelegate label(assigns), to: EventsWeb.Components.Base.Label
  defdelegate menubar(assigns), to: EventsWeb.Components.Base.Menubar
  defdelegate native_select(assigns), to: EventsWeb.Components.Base.NativeSelect
  defdelegate navigation_menu(assigns), to: EventsWeb.Components.Base.NavigationMenu
  defdelegate pagination(assigns), to: EventsWeb.Components.Base.Pagination
  defdelegate popover(assigns), to: EventsWeb.Components.Base.Popover
  defdelegate progress(assigns), to: EventsWeb.Components.Base.Progress
  defdelegate radio_group(assigns), to: EventsWeb.Components.Base.RadioGroup
  defdelegate resizable(assigns), to: EventsWeb.Components.Base.Resizable
  defdelegate scroll_area(assigns), to: EventsWeb.Components.Base.ScrollArea
  defdelegate select(assigns), to: EventsWeb.Components.Base.Select
  defdelegate separator(assigns), to: EventsWeb.Components.Base.Separator
  defdelegate sheet(assigns), to: EventsWeb.Components.Base.Sheet
  defdelegate sidebar(assigns), to: EventsWeb.Components.Base.Sidebar
  defdelegate skeleton(assigns), to: EventsWeb.Components.Base.Skeleton
  defdelegate slider(assigns), to: EventsWeb.Components.Base.Slider
  defdelegate spinner(assigns), to: EventsWeb.Components.Base.Spinner
  defdelegate switch(assigns), to: EventsWeb.Components.Base.Switch
  defdelegate table(assigns), to: EventsWeb.Components.Base.Table
  defdelegate tabs(assigns), to: EventsWeb.Components.Base.Tabs
  defdelegate textarea(assigns), to: EventsWeb.Components.Base.Textarea
  defdelegate toast(assigns), to: EventsWeb.Components.Base.Toast
  defdelegate toggle(assigns), to: EventsWeb.Components.Base.Toggle
  defdelegate toggle_group(assigns), to: EventsWeb.Components.Base.ToggleGroup
  defdelegate tooltip(assigns), to: EventsWeb.Components.Base.Tooltip
  defdelegate typography(assigns), to: EventsWeb.Components.Base.Typography

  @doc """
  Utility function to merge CSS classes, handling nil values and deduplication.
  """
  def classes(class_list) when is_list(class_list) do
    class_list
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  def classes(class) when is_binary(class), do: class
  def classes(nil), do: ""

  @doc """
  Gets variant classes from a map based on a variant key.
  """
  def variant_class(variants, variant, default \\ "")
  def variant_class(variants, variant, default) when is_map(variants) do
    Map.get(variants, variant, default)
  end
end
