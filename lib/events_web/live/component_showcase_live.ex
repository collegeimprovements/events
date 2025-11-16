defmodule EventsWeb.ComponentShowcaseLive do
  @moduledoc """
  Showcase page for all Base UI components.

  Demonstrates every component with various configurations and states.
  """
  use EventsWeb, :live_view
  import EventsWeb.Components.Base

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Component Showcase")
     |> assign(:current_tab, "buttons")
     |> assign(:dialog_open, false)
     |> assign(:sheet_open, false)
     |> assign(:form_data, %{})
     |> assign(:table_data, generate_table_data())
     |> assign(:current_page, 1)
     |> assign(:toast_visible, false)}
  end

  @impl true
  def handle_event("change-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  def handle_event("toggle-dialog", _, socket) do
    {:noreply, update(socket, :dialog_open, &(!&1))}
  end

  def handle_event("toggle-sheet", _, socket) do
    {:noreply, update(socket, :sheet_open, &(!&1))}
  end

  def handle_event("show-toast", _, socket) do
    {:noreply, assign(socket, :toast_visible, true)}
  end

  def handle_event("page-change", %{"page" => page}, socket) do
    {:noreply, assign(socket, :current_page, String.to_integer(page))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-zinc-50 via-white to-zinc-50">
      <%!-- Header --%>
      <header class="sticky top-0 z-40 border-b border-zinc-200 bg-white/80 backdrop-blur-sm">
        <div class="container mx-auto px-4 py-4">
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-3xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
                Base UI Components
              </h1>
              <p class="text-sm text-zinc-500 mt-1">
                54 production-ready components for Phoenix LiveView
              </p>
            </div>
            <div class="flex gap-2">
              <.badge variant="success">v1.0</.badge>
              <.badge variant="info">54 Components</.badge>
            </div>
          </div>
        </div>
      </header>

      <%!-- Main Content --%>
      <div class="container mx-auto px-4 py-8">
        <%!-- Navigation Tabs --%>
        <.tabs default_value={@current_tab}>
          <:list>
            <:trigger value="buttons" phx-click="change-tab" phx-value-tab="buttons">
              Buttons & Actions
            </:trigger>
            <:trigger value="forms" phx-click="change-tab" phx-value-tab="forms">
              Form Components
            </:trigger>
            <:trigger value="display" phx-click="change-tab" phx-value-tab="display">
              Display Components
            </:trigger>
            <:trigger value="overlays" phx-click="change-tab" phx-value-tab="overlays">
              Overlays & Dialogs
            </:trigger>
            <:trigger value="navigation" phx-click="change-tab" phx-value-tab="navigation">
              Navigation
            </:trigger>
            <:trigger value="data" phx-click="change-tab" phx-value-tab="data">
              Data Display
            </:trigger>
          </:list>

          <%!-- Button Components --%>
          <:content value="buttons">
            <.render_buttons_section />
          </:content>

          <%!-- Form Components --%>
          <:content value="forms">
            <.render_forms_section />
          </:content>

          <%!-- Display Components --%>
          <:content value="display">
            <.render_display_section />
          </:content>

          <%!-- Overlays --%>
          <:content value="overlays">
            <.render_overlays_section dialog_open={@dialog_open} sheet_open={@sheet_open} />
          </:content>

          <%!-- Navigation --%>
          <:content value="navigation">
            <.render_navigation_section current_page={@current_page} />
          </:content>

          <%!-- Data Display --%>
          <:content value="data">
            <.render_data_section table_data={@table_data} />
          </:content>
        </.tabs>
      </div>

      <%!-- Toast Container --%>
      <div :if={@toast_visible} class="fixed bottom-4 right-4 z-50">
        <.toast variant="success">
          <:title>Success!</:title>
          <:description>Component interaction successful</:description>
        </.toast>
      </div>
    </div>
    """
  end

  ## Section Renders

  attr :rest, :global
  defp render_buttons_section(assigns) do
    ~H"""
    <div class="space-y-8" {@rest}>
      <%!-- Buttons --%>
      <.showcase_card title="Buttons" description="Interactive button components with multiple variants">
        <div class="flex flex-wrap gap-3">
          <.button variant="default">Default</.button>
          <.button variant="primary">Primary</.button>
          <.button variant="secondary">Secondary</.button>
          <.button variant="outline">Outline</.button>
          <.button variant="ghost">Ghost</.button>
          <.button variant="destructive">Destructive</.button>
          <.button variant="link">Link</.button>
        </div>

        <.separator class="my-4" />

        <div class="flex flex-wrap items-center gap-3">
          <.button size="sm">Small</.button>
          <.button size="default">Default</.button>
          <.button size="lg">Large</.button>
          <.button size="icon">
            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
            </svg>
          </.button>
        </div>
      </.showcase_card>

      <%!-- Button Groups --%>
      <.showcase_card title="Button Groups" description="Group related actions together">
        <.button_group>
          <.button variant="outline">Left</.button>
          <.button variant="outline">Center</.button>
          <.button variant="outline">Right</.button>
        </.button_group>
      </.showcase_card>

      <%!-- Toggle & Toggle Group --%>
      <.showcase_card title="Toggles" description="Toggle buttons for binary and multi-select options">
        <div class="space-y-4">
          <div class="flex gap-2">
            <.toggle>Bold</.toggle>
            <.toggle pressed>Italic</.toggle>
            <.toggle>Underline</.toggle>
          </div>

          <.toggle_group type="single" name="alignment">
            <:item value="left">Left</:item>
            <:item value="center">Center</:item>
            <:item value="right">Right</:item>
          </.toggle_group>
        </div>
      </.showcase_card>
    </div>
    """
  end

  defp render_forms_section(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Input Components --%>
      <.showcase_card title="Input Fields" description="Text input with various states">
        <div class="space-y-4 max-w-md">
          <.input name="text" placeholder="Enter text" />
          <.input name="email" type="email" placeholder="Email address" />
          <.input name="password" type="password" placeholder="Password" />
          <.input name="error_example" error="This field is required" placeholder="With error" />
          <.input name="disabled" disabled placeholder="Disabled input" />
        </div>
      </.showcase_card>

      <%!-- Labels and Fields --%>
      <.showcase_card title="Form Fields" description="Complete form field with label and description">
        <div class="space-y-4 max-w-md">
          <.field name="username" label="Username" required>
            <:description>Choose a unique username</:description>
          </.field>

          <.field name="bio" label="Bio">
            <:input>
              <.textarea name="bio" rows={4} placeholder="Tell us about yourself" />
            </:input>
            <:description>Brief description for your profile</:description>
          </.field>
        </div>
      </.showcase_card>

      <%!-- Checkboxes and Radio Groups --%>
      <.showcase_card title="Selection Controls" description="Checkboxes, radios, and switches">
        <div class="space-y-6">
          <div>
            <p class="text-sm font-medium mb-3">Checkboxes</p>
            <div class="space-y-2">
              <.checkbox name="terms" label="I agree to the terms and conditions" />
              <.checkbox name="newsletter" label="Subscribe to newsletter" checked />
              <.checkbox name="disabled" label="Disabled option" disabled />
            </div>
          </div>

          <div>
            <p class="text-sm font-medium mb-3">Radio Groups</p>
            <.radio_group name="plan">
              <:radio value="free" label="Free Plan" />
              <:radio value="pro" label="Pro Plan" checked />
              <:radio value="enterprise" label="Enterprise Plan" />
            </.radio_group>
          </div>

          <div>
            <p class="text-sm font-medium mb-3">Switches</p>
            <div class="space-y-2">
              <.switch name="notifications" label="Enable notifications" />
              <.switch name="marketing" label="Marketing emails" checked />
              <.switch name="disabled_switch" label="Disabled" disabled />
            </div>
          </div>
        </div>
      </.showcase_card>

      <%!-- Select Components --%>
      <.showcase_card title="Select Dropdowns" description="Native and custom select components">
        <div class="space-y-4 max-w-md">
          <.native_select name="country" placeholder="Select a country">
            <:option value="us">United States</:option>
            <:option value="uk">United Kingdom</:option>
            <:option value="ca">Canada</:option>
          </.native_select>

          <.slider name="volume" value={75} show_value />
        </div>
      </.showcase_card>
    </div>
    """
  end

  defp render_display_section(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Avatars --%>
      <.showcase_card title="Avatars" description="User profile images with fallbacks">
        <div class="flex flex-wrap items-center gap-4">
          <.avatar alt="John Doe" />
          <.avatar alt="Jane Smith" size="sm" />
          <.avatar alt="Bob Johnson" size="lg" />
          <.avatar alt="Alice Williams" size="xl" />
          <.avatar fallback="AB" size="lg" />
        </div>
      </.showcase_card>

      <%!-- Badges --%>
      <.showcase_card title="Badges" description="Status indicators and labels">
        <div class="flex flex-wrap gap-2">
          <.badge>Default</.badge>
          <.badge variant="success">Success</.badge>
          <.badge variant="warning">Warning</.badge>
          <.badge variant="error">Error</.badge>
          <.badge variant="info">Info</.badge>
          <.badge variant="outline">Outline</.badge>
          <.badge variant="secondary">Secondary</.badge>
        </div>
      </.showcase_card>

      <%!-- Alerts --%>
      <.showcase_card title="Alerts" description="Important messages and notifications">
        <div class="space-y-4">
          <.alert variant="default">
            <.alert_title>Default Alert</.alert_title>
            <.alert_description>This is a default alert message.</.alert_description>
          </.alert>

          <.alert variant="info" dismissible>
            <.alert_title>Information</.alert_title>
            <.alert_description>This alert can be dismissed.</.alert_description>
          </.alert>

          <.alert variant="success">
            <.alert_title>Success!</.alert_title>
            <.alert_description>Your operation completed successfully.</.alert_description>
          </.alert>

          <.alert variant="warning">
            <.alert_title>Warning</.alert_title>
            <.alert_description>Please review before proceeding.</.alert_description>
          </.alert>

          <.alert variant="error">
            <.alert_title>Error</.alert_title>
            <.alert_description>Something went wrong. Please try again.</.alert_description>
          </.alert>
        </div>
      </.showcase_card>

      <%!-- Cards --%>
      <.showcase_card title="Cards" description="Content containers with header, body, and footer">
        <div class="grid gap-4 md:grid-cols-2">
          <.card>
            <.card_header>
              <.card_title>Simple Card</.card_title>
              <.card_description>A basic card example</.card_description>
            </.card_header>
            <.card_content>
              <p class="text-sm text-zinc-600">
                This is the main content area of the card.
              </p>
            </.card_content>
            <.card_footer>
              <.button size="sm">Action</.button>
            </.card_footer>
          </.card>

          <.card>
            <.card_header>
              <.card_title>Statistics</.card_title>
            </.card_header>
            <.card_content>
              <div class="space-y-2">
                <div class="flex justify-between items-center">
                  <span class="text-sm text-zinc-500">Total Users</span>
                  <span class="text-2xl font-bold">1,234</span>
                </div>
                <.progress value={75} show_label />
              </div>
            </.card_content>
          </.card>
        </div>
      </.showcase_card>

      <%!-- Loading States --%>
      <.showcase_card title="Loading States" description="Skeletons and spinners">
        <div class="space-y-4">
          <div class="flex gap-4">
            <.spinner />
            <.spinner size="sm" />
            <.spinner size="lg" />
            <.spinner size="xl" />
          </div>

          <div class="space-y-3 max-w-md">
            <.skeleton class="h-4 w-full" />
            <.skeleton class="h-4 w-3/4" />
            <.skeleton class="h-4 w-1/2" />
            <.skeleton class="h-12 w-12 rounded-full" />
          </div>
        </div>
      </.showcase_card>

      <%!-- Typography --%>
      <.showcase_card title="Typography" description="Text styles and formatting">
        <div class="space-y-4">
          <.typography variant="h1">Heading 1</.typography>
          <.typography variant="h2">Heading 2</.typography>
          <.typography variant="h3">Heading 3</.typography>
          <.typography variant="p">
            This is a paragraph with regular text styling.
          </.typography>
          <.typography variant="lead">
            This is lead text for important paragraphs.
          </.typography>
          <.typography variant="muted">
            This is muted text for less important information.
          </.typography>
          <.typography variant="code">const example = true;</.typography>
        </div>
      </.showcase_card>

      <%!-- Progress and Indicators --%>
      <.showcase_card title="Progress Indicators" description="Show task completion">
        <div class="space-y-4">
          <.progress value={25} />
          <.progress value={50} variant="primary" show_label />
          <.progress value={75} variant="success" show_label />
          <.progress value={100} variant="success" />
        </div>
      </.showcase_card>
    </div>
    """
  end

  attr :dialog_open, :boolean, required: true
  attr :sheet_open, :boolean, required: true

  defp render_overlays_section(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Tooltips --%>
      <.showcase_card title="Tooltips" description="Helpful information on hover">
        <div class="flex gap-4">
          <.tooltip content="This is a tooltip">
            <.button variant="outline">Hover me</.button>
          </.tooltip>

          <.tooltip content="Tooltip on right" side="right">
            <.button variant="outline">Right</.button>
          </.tooltip>

          <.tooltip content="Tooltip on bottom" side="bottom">
            <.button variant="outline">Bottom</.button>
          </.tooltip>
        </div>
      </.showcase_card>

      <%!-- Popovers --%>
      <.showcase_card title="Popovers" description="Floating content panels">
        <.popover id="example-popover">
          <:trigger>
            <.button variant="outline">Open Popover</.button>
          </:trigger>
          <:content>
            <div class="space-y-2">
              <h4 class="font-medium">Popover Title</h4>
              <p class="text-sm text-zinc-500">
                This is a popover with custom content.
              </p>
            </div>
          </:content>
        </.popover>
      </.showcase_card>

      <%!-- Dialogs --%>
      <.showcase_card title="Dialogs" description="Modal windows for important actions">
        <.button phx-click="toggle-dialog">Open Dialog</.button>

        <.dialog id="example-dialog" open={@dialog_open}>
          <:content>
            <.dialog_header>
              <.dialog_title>Confirm Action</.dialog_title>
              <.dialog_description>
                Are you sure you want to proceed with this action?
              </.dialog_description>
            </.dialog_header>
            <.dialog_body>
              <p class="text-sm text-zinc-600">
                This action cannot be undone.
              </p>
            </.dialog_body>
            <.dialog_footer>
              <.button variant="outline" phx-click="toggle-dialog">Cancel</.button>
              <.button phx-click="toggle-dialog">Confirm</.button>
            </.dialog_footer>
          </:content>
        </.dialog>
      </.showcase_card>

      <%!-- Sheets --%>
      <.showcase_card title="Sheets" description="Side panels for additional content">
        <.button phx-click="toggle-sheet">Open Sheet</.button>

        <.sheet id="example-sheet" open={@sheet_open} side="right">
          <:header>
            <:title>Sheet Title</:title>
            <:description>Additional information panel</:description>
          </:header>
          <:content>
            <div class="space-y-4">
              <p class="text-sm">This is a sheet component with content.</p>
              <.button class="w-full">Action Button</.button>
            </div>
          </:content>
          <:footer>
            <.button variant="outline" phx-click="toggle-sheet" class="w-full">Close</.button>
          </:footer>
        </.sheet>
      </.showcase_card>

      <%!-- Accordion --%>
      <.showcase_card title="Accordion" description="Collapsible content sections">
        <.accordion>
          <:item title="Section 1" value="1" open>
            Content for the first section. This section is open by default.
          </:item>
          <:item title="Section 2" value="2">
            Content for the second section.
          </:item>
          <:item title="Section 3" value="3">
            Content for the third section.
          </:item>
        </.accordion>
      </.showcase_card>

      <%!-- Collapsible --%>
      <.showcase_card title="Collapsible" description="Expandable content">
        <.collapsible>
          <:trigger>
            <.button variant="ghost">Toggle Content</.button>
          </:trigger>
          <:content>
            <div class="mt-4 rounded-lg border border-zinc-200 p-4">
              <p class="text-sm text-zinc-600">
                This content can be shown or hidden.
              </p>
            </div>
          </:content>
        </.collapsible>
      </.showcase_card>
    </div>
    """
  end

  attr :current_page, :integer, required: true

  defp render_navigation_section(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Breadcrumbs --%>
      <.showcase_card title="Breadcrumbs" description="Navigation hierarchy">
        <.breadcrumb>
          <:item href="/">Home</:item>
          <:item href="/docs">Documentation</:item>
          <:item>Components</:item>
        </.breadcrumb>
      </.showcase_card>

      <%!-- Navigation Menu --%>
      <.showcase_card title="Navigation Menu" description="Site navigation links">
        <.navigation_menu>
          <:item active>Dashboard</:item>
          <:item>Projects</:item>
          <:item>Team</:item>
          <:item>Settings</:item>
        </.navigation_menu>
      </.showcase_card>

      <%!-- Pagination --%>
      <.showcase_card title="Pagination" description="Page navigation">
        <.pagination
          current_page={@current_page}
          total_pages={10}
          on_page_change="page-change"
        />
      </.showcase_card>

      <%!-- Separator --%>
      <.showcase_card title="Separators" description="Visual content dividers">
        <div class="space-y-4">
          <div>
            <p>Content above</p>
            <.separator class="my-4" />
            <p>Content below</p>
          </div>

          <div class="flex items-center gap-4 h-12">
            <span>Left</span>
            <.separator orientation="vertical" />
            <span>Right</span>
          </div>
        </div>
      </.showcase_card>
    </div>
    """
  end

  attr :table_data, :list, required: true

  defp render_data_section(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Table --%>
      <.showcase_card title="Tables" description="Data tables with headers and rows">
        <.table>
          <:header>
            <:column>Name</:column>
            <:column>Email</:column>
            <:column>Status</:column>
            <:column>Actions</:column>
          </:header>
          <%= for row <- @table_data do %>
            <:row>
              <:cell><%= row.name %></:cell>
              <:cell><%= row.email %></:cell>
              <:cell>
                <.badge variant={if row.active, do: "success", else: "error"}>
                  <%= if row.active, do: "Active", else: "Inactive" %>
                </.badge>
              </:cell>
              <:cell>
                <.button size="sm" variant="ghost">Edit</.button>
              </:cell>
            </:row>
          <% end %>
        </.table>
      </.showcase_card>

      <%!-- Empty State --%>
      <.showcase_card title="Empty States" description="Placeholder for empty data">
        <.empty>
          <:title>No results found</:title>
          <:description>Try adjusting your search or filter criteria</:description>
          <:action>
            <.button>Clear Filters</.button>
          </:action>
        </.empty>
      </.showcase_card>

      <%!-- Item Component --%>
      <.showcase_card title="Item Lists" description="List items with leading and trailing content">
        <div class="space-y-2">
          <.item clickable>
            <:leading>
              <.avatar alt="User One" size="sm" />
            </:leading>
            <:content>
              <:title>User One</:title>
              <:description>user@example.com</:description>
            </:content>
            <:trailing>
              <.badge variant="success">Pro</.badge>
            </:trailing>
          </.item>

          <.item>
            <:leading>
              <.avatar alt="User Two" size="sm" />
            </:leading>
            <:content>
              <:title>User Two</:title>
              <:description>another@example.com</:description>
            </:content>
            <:trailing>
              <.button size="sm" variant="ghost">View</.button>
            </:trailing>
          </.item>
        </div>
      </.showcase_card>

      <%!-- Kbd --%>
      <.showcase_card title="Keyboard Shortcuts" description="Display keyboard commands">
        <div class="flex gap-2">
          <.kbd>⌘</.kbd>
          <span>+</span>
          <.kbd>K</.kbd>
          <span class="text-sm text-zinc-500 ml-2">to open command palette</span>
        </div>
      </.showcase_card>
    </div>
    """
  end

  ## Helper Components

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  defp showcase_card(assigns) do
    ~H"""
    <.card class="overflow-hidden">
      <.card_header class="bg-gradient-to-r from-zinc-50 to-white">
        <.card_title class="text-lg"><%= @title %></.card_title>
        <.card_description :if={@description}><%= @description %></.card_description>
      </.card_header>
      <.card_content class="pt-6">
        <%= render_slot(@inner_block) %>
      </.card_content>
    </.card>
    """
  end

  ## Data Generators

  defp generate_table_data do
    [
      %{name: "John Doe", email: "john@example.com", active: true},
      %{name: "Jane Smith", email: "jane@example.com", active: true},
      %{name: "Bob Johnson", email: "bob@example.com", active: false},
      %{name: "Alice Williams", email: "alice@example.com", active: true}
    ]
  end
end
