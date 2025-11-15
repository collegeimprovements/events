# Base UI Components - Comprehensive Examples

This guide demonstrates the improved composability and reusability patterns of the Base UI component library.

## Key Improvements

1. **Shared Utilities** - Common variant systems and class management
2. **Composable Sub-Components** - Flat, flexible component structures
3. **Consistent Patterns** - Predictable APIs across all components
4. **Better Reusability** - Shared base classes and variant maps

## Core Patterns

### 1. Composable Card Structure

The Card component is now split into composable sub-components for maximum flexibility:

```heex
<%# Old nested slot pattern %>
<.card>
  <:header>
    <:title>Card Title</:title>
    <:description>Description</:description>
  </:header>
  <:content>Content</:content>
  <:footer>Actions</:footer>
</.card>

<%# New flat, composable pattern %>
<.card>
  <.card_header>
    <.card_title>Card Title</.card_title>
    <.card_description>Description</.card_description>
  </.card_header>
  <.card_content>
    Content goes here
  </.card_content>
  <.card_footer>
    <.button>Action</.button>
  </.card_footer>
</.card>

<%# Minimal card - only use what you need %>
<.card>
  <.card_content>
    Just content, no header or footer
  </.card_content>
</.card>

<%# Card with custom structure %>
<.card class="hover:shadow-xl transition-shadow">
  <.card_header class="bg-gradient-to-r from-blue-500 to-purple-500 text-white">
    <.card_title>Custom Styled</.card_title>
  </.card_header>
  <.card_content class="grid grid-cols-2 gap-4">
    <div>Column 1</div>
    <div>Column 2</div>
  </.card_content>
</.card>
```

### 2. Composable Dialog Structure

Dialogs follow the same flat, composable pattern:

```heex
<%# Full featured dialog %>
<.dialog id="user-dialog">
  <:trigger>
    <.button>Edit Profile</.button>
  </:trigger>
  <:content>
    <.dialog_header>
      <.dialog_title>Edit Profile</.dialog_title>
      <.dialog_description>
        Make changes to your profile here.
      </.dialog_description>
    </.dialog_header>
    <.dialog_body>
      <.field name="name" label="Name" />
      <.field name="email" label="Email" type="email" />
    </.dialog_body>
    <.dialog_footer>
      <.button variant="outline" phx-click={hide_dialog("user-dialog")}>
        Cancel
      </.button>
      <.button type="submit">Save Changes</.button>
    </.dialog_footer>
  </:content>
</.dialog>

<%# Simple dialog %>
<.dialog id="simple">
  <:trigger><.button>Info</.button></:trigger>
  <:content>
    <.dialog_body>
      <p>Simple message without header/footer</p>
    </dialog_body>
  </:content>
</.dialog>
```

### 3. Composable Alert Structure

Alerts are now more flexible:

```heex
<%# With sub-components %>
<.alert variant="info" dismissible>
  <.alert_title>Did you know?</.alert_title>
  <.alert_description>
    You can use keyboard shortcuts to navigate faster.
  </.alert_description>
</.alert>

<%# Simple alert %>
<.alert variant="success">
  Your changes have been saved successfully!
</.alert>

<%# Custom structured alert %>
<.alert variant="warning">
  <div class="flex gap-3">
    <svg class="h-5 w-5 shrink-0" />
    <div>
      <.alert_title>Warning</.alert_title>
      <.alert_description>
        This action cannot be undone.
      </.alert_description>
    </div>
  </div>
</.alert>
```

### 4. Shared Variant Systems

All components now use shared variant maps for consistency:

```heex
<%# Button variants - same as other interactive components %>
<.button variant="default">Default</.button>
<.button variant="primary">Primary</.button>
<.button variant="destructive">Delete</.button>

<%# Status variants - consistent across Alert, Badge, Toast %>
<.alert variant="success">Success message</.alert>
<.badge variant="success">Success</.badge>
<.toast variant="success">
  <:title>Success</:title>
</.toast>

<%# Size variants - shared across components %>
<.button size="sm">Small</.button>
<.button size="default">Default</.button>
<.button size="lg">Large</.button>
<.button size="icon"><.icon name="hero-cog" /></.button>
```

### 5. Utility Class Management

Better class merging and override support:

```heex
<%# Classes are properly merged with later values overriding %>
<.button class="bg-green-600 hover:bg-green-700">
  Custom colored button
</.button>

<%# Combine multiple utility classes %>
<.card class="max-w-md mx-auto shadow-2xl">
  <.card_content class="p-8">
    Centered card with custom spacing
  </.card_content>
</.card>
```

## Component Composition Patterns

### Building Complex UIs

```heex
<%# User profile card with multiple components %>
<.card class="w-full max-w-2xl">
  <.card_header>
    <div class="flex items-center gap-4">
      <.avatar src="/user.jpg" alt="John Doe" size="lg" />
      <div>
        <.card_title>John Doe</.card_title>
        <.card_description>Software Engineer</.card_description>
      </div>
      <div class="ml-auto flex gap-2">
        <.badge variant="success">Active</.badge>
        <.badge variant="info">Pro</.badge>
      </div>
    </div>
  </.card_header>
  <.card_content>
    <.separator class="mb-4" />
    <div class="grid grid-cols-2 gap-4">
      <div>
        <p class="text-sm text-zinc-500">Email</p>
        <p class="font-medium">john@example.com</p>
      </div>
      <div>
        <p class="text-sm text-zinc-500">Location</p>
        <p class="font-medium">San Francisco, CA</p>
      </div>
    </div>
  </.card_content>
  <.card_footer class="justify-between">
    <.button variant="outline">View Profile</.button>
    <.button>Send Message</.button>
  </.card_footer>
</.card>
```

### Dashboard Stats Grid

```heex
<div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
  <%= for stat <- @stats do %>
    <.card>
      <.card_header class="flex flex-row items-center justify-between pb-2">
        <.card_title class="text-sm font-medium">
          <%= stat.title %>
        </.card_title>
        <.icon name={stat.icon} class="h-4 w-4 text-zinc-500" />
      </.card_header>
      <.card_content>
        <div class="text-2xl font-bold"><%= stat.value %></div>
        <p class="text-xs text-zinc-500">
          <%= stat.change %> from last month
        </p>
      </.card_content>
    </.card>
  <% end %>
</div>
```

### Form with Validation

```heex
<.card class="max-w-md">
  <.card_header>
    <.card_title>Create Account</.card_title>
    <.card_description>
      Enter your information to get started
    </.card_description>
  </.card_header>
  <.card_content>
    <form phx-submit="register" class="space-y-4">
      <.field name="name" label="Full Name" required>
        <:description>Your full legal name</:description>
      </.field>

      <.field name="email" label="Email" type="email" required />

      <.field name="password" label="Password" type="password" required>
        <:description>Must be at least 8 characters</:description>
      </.field>

      <.checkbox name="terms" label="I agree to the terms and conditions" />

      <.button type="submit" class="w-full">
        Create Account
      </.button>
    </form>
  </.card_content>
</./card>
```

### Data Table with Actions

```heex
<.card>
  <.card_header>
    <div class="flex items-center justify-between">
      <.card_title>Users</.card_title>
      <.button size="sm">Add User</.button>
    </div>
  </.card_header>
  <.card_content class="p-0">
    <.table>
      <:header>
        <:column>Name</:column>
        <:column>Email</:column>
        <:column>Role</:column>
        <:column>Status</:column>
        <:column>Actions</:column>
      </:header>
      <%= for user <- @users do %>
        <:row>
          <:cell>
            <div class="flex items-center gap-2">
              <.avatar src={user.avatar} alt={user.name} size="sm" />
              <%= user.name %>
            </div>
          </:cell>
          <:cell><%= user.email %></:cell>
          <:cell>
            <.badge variant="secondary"><%= user.role %></.badge>
          </:cell>
          <:cell>
            <.badge variant={user.active && "success" || "error"}>
              <%= user.active && "Active" || "Inactive" %>
            </.badge>
          </:cell>
          <:cell>
            <.dropdown_menu id={"user-#{user.id}-menu"}>
              <:trigger>
                <.button variant="ghost" size="icon">
                  <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
                </.button>
              </:trigger>
              <:item phx-click="edit-user" phx-value-id={user.id}>Edit</:item>
              <:item phx-click="deactivate" phx-value-id={user.id}>Deactivate</:item>
              <:separator />
              <:item phx-click="delete" phx-value-id={user.id}>Delete</:item>
            </.dropdown_menu>
          </:cell>
        </:row>
      <% end %>
    </.table>
  </.card_content>
  <.card_footer>
    <.pagination current_page={@page} total_pages={@total_pages} />
  </.card_footer>
</.card>
```

## Reusability Patterns

### Custom Stat Card Component

```elixir
# Create reusable components by composing base components
attr :title, :string, required: true
attr :value, :string, required: true
attr :change, :string
attr :icon, :string

def stat_card(assigns) do
  ~H"""
  <.card>
    <.card_header class="flex flex-row items-center justify-between space-y-0 pb-2">
      <.card_title class="text-sm font-medium"><%= @title %></.card_title>
      <.icon :if={@icon} name={@icon} class="h-4 w-4 text-muted-foreground" />
    </.card_header>
    <.card_content>
      <div class="text-2xl font-bold"><%= @value %></div>
      <p :if={@change} class="text-xs text-zinc-500"><%= @change %></p>
    </.card_content>
  </.card>
  """
end
```

### Custom Alert Component

```elixir
# Wrap base components for domain-specific use
attr :type, :atom, values: [:info, :warning, :error, :success]
attr :message, :string, required: true
attr :dismissible, :boolean, default: true

def notification(assigns) do
  ~H"""
  <.alert variant={Atom.to_string(@type)} dismissible={@dismissible}>
    <div class="flex gap-3">
      <%= case @type do %>
        <% :success -> %><.icon name="hero-check-circle" class="h-5 w-5" />
        <% :error -> %><.icon name="hero-x-circle" class="h-5 w-5" />
        <% :warning -> %><.icon name="hero-exclamation-triangle" class="h-5 w-5" />
        <% :info -> %><.icon name="hero-information-circle" class="h-5 w-5" />
      <% end %>
      <.alert_description><%= @message %></.alert_description>
    </div>
  </.alert>
  """
end
```

## Best Practices

1. **Use Sub-Components** - Leverage card_*, dialog_*, alert_* for better structure
2. **Compose Over Configure** - Build complex UIs by combining simple components
3. **Shared Variants** - Use consistent variant names across components
4. **Class Overrides** - Use the `class` attribute to customize without modifying components
5. **Utility Functions** - Import Utils for access to shared class/variant functions

## Migration from Old Patterns

### Card Component

```heex
<%# Before (nested slots) %>
<.card>
  <:header>
    <:title>Title</:title>
  </:header>
  <:content>Content</:content>
</.card>

<%# After (composable) %>
<.card>
  <.card_header>
    <.card_title>Title</.card_title>
  </.card_header>
  <.card_content>Content</.card_content>
</.card>
```

### Alert Component

```heex
<%# Before (slots) %>
<.alert>
  <:title>Title</:title>
  <:description>Description</:description>
</.alert>

<%# After (sub-components) %>
<.alert>
  <.alert_title>Title</.alert_title>
  <.alert_description>Description</.alert_description>
</.alert>
```

## Performance Benefits

- **Reduced Complexity** - Flat component structures are easier to understand
- **Better Tree Shaking** - Only import what you use
- **Consistent Rendering** - Shared utilities ensure uniform output
- **Easier Testing** - Sub-components can be tested independently
