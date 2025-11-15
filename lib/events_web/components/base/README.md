# Base UI Components for Phoenix LiveView

A comprehensive UI component library for Phoenix LiveView, inspired by shadcn/ui and Base UI. This library provides 54 accessible, customizable components built with Tailwind CSS.

## Features

- ✅ **54 Components** - Complete set of UI components for modern web applications
- ✅ **Accessibility First** - Built with ARIA attributes and keyboard navigation
- ✅ **Tailwind CSS** - Utility-first styling with organized, maintainable classes
- ✅ **Phoenix LiveView** - Native integration with LiveView components
- ✅ **Colocated JavaScript** - Interactive features with dedicated hooks
- ✅ **Type Safe** - Component attributes with validation
- ✅ **Consistent API** - Predictable component interfaces across the library

## Installation

Add to your LiveView module:

```elixir
import EventsWeb.Components.Base
```

Or import in your `events_web.ex`:

```elixir
def html do
  quote do
    use Phoenix.Component
    import EventsWeb.Components.Base
    # ...
  end
end
```

## Components List

### Display Components
- **Alert** - Display important messages with variants (default, info, success, warning, error)
- **Avatar** - User profile images with fallback support
- **Badge** - Labels and status indicators with multiple variants
- **Card** - Container for related content with header, content, and footer
- **Empty** - Empty state placeholder with icon, title, description, and actions
- **Item** - Versatile container for list items with leading, content, and trailing slots
- **Kbd** - Display keyboard shortcuts
- **Progress** - Task completion indicator with variants
- **Separator** - Visual content divider (horizontal/vertical)
- **Skeleton** - Loading state placeholder
- **Spinner** - Loading indicator with multiple sizes
- **Typography** - Consistent text styling (h1-h6, p, lead, large, small, muted, code)

### Form Components
- **Checkbox** - Boolean selection with label support
- **Field** - Combines label, input, and help text
- **Input** - Text input with error states
- **InputGroup** - Input with prefix/suffix decorations
- **InputOTP** - One-time password entry with auto-focus
- **Label** - Form input labels with required indicator
- **NativeSelect** - Styled HTML select element
- **RadioGroup** - Single selection from multiple options
- **Select** - Custom select with search (requires JS hook)
- **Slider** - Value selection within a range
- **Switch** - Toggle control
- **Textarea** - Multi-line text input

### Button Components
- **Button** - Interactive buttons with variants (default, primary, secondary, outline, ghost, destructive, link)
- **ButtonGroup** - Group related buttons
- **Toggle** - Two-state toggle button
- **ToggleGroup** - Grouped toggle buttons (single/multiple selection)

### Navigation Components
- **Breadcrumb** - Hierarchical navigation path
- **NavigationMenu** - Site navigation links
- **Pagination** - Page navigation controls
- **Sidebar** - Navigation sidebar with collapsible support

### Layout Components
- **Accordion** - Collapsible content sections
- **Collapsible** - Expandable content
- **ResizableResizable** - Adjustable panel layouts
- **ScrollArea** - Custom scrollbar styling
- **Tabs** - Tabbed content panels
- **Table** - Tabular data display

### Overlay Components
- **AlertDialog** - Important confirmations
- **Dialog** - Modal windows
- **Drawer** - Side panel (alias for Sheet)
- **HoverCard** - Rich preview on hover
- **Popover** - Floating content
- **Sheet** - Side panels from any direction
- **Toast** - Temporary notifications
- **Tooltip** - Helpful information on hover/focus

### Menu Components
- **Command** - Command palette/search
- **Combobox** - Searchable select
- **ContextMenu** - Right-click menus
- **DropdownMenu** - Action menus
- **Menubar** - Application menu bar

### Date Components
- **Calendar** - Date selection calendar
- **DatePicker** - Input with calendar picker

### Advanced Components
- **Carousel** - Sliding content with auto-play
- **Combobox** - Autocomplete search
- **Command** - Command palette

## Usage Examples

### Basic Components

```heex
<!-- Button -->
<.button>Click me</.button>
<.button variant="primary" size="lg">Large Primary</.button>

<!-- Badge -->
<.badge variant="success">Active</.badge>
<.badge variant="error">Offline</.badge>

<!-- Alert -->
<.alert variant="info" dismissible>
  <:title>Information</:title>
  <:description>This is an informational message.</:description>
</.alert>
```

### Form Components

```heex
<!-- Simple Input -->
<.input type="email" name="email" placeholder="Enter email" />

<!-- Field with Label -->
<.field name="username" label="Username" required>
  <:description>Choose a unique username</:description>
</.field>

<!-- Checkbox with Label -->
<.checkbox name="agree" label="I agree to the terms" />

<!-- Radio Group -->
<.radio_group name="plan">
  <:radio value="free" label="Free Plan" />
  <:radio value="pro" label="Pro Plan" checked />
  <:radio value="enterprise" label="Enterprise" />
</.radio_group>

<!-- Switch -->
<.switch name="notifications" label="Enable notifications" checked />
```

### Layout Components

```heex
<!-- Card -->
<.card>
  <:header>
    <:title>Card Title</:title>
    <:description>Card description</:description>
  </:header>
  <:content>
    <p>Card content goes here</p>
  </:content>
  <:footer>
    <.button>Action</.button>
  </:footer>
</.card>

<!-- Tabs -->
<.tabs default_value="account">
  <:list>
    <:trigger value="account">Account</:trigger>
    <:trigger value="password">Password</:trigger>
  </:list>
  <:content value="account">Account settings</:content>
  <:content value="password">Password settings</:content>
</.tabs>

<!-- Accordion -->
<.accordion>
  <:item title="Section 1" value="1">
    Content for section 1
  </:item>
  <:item title="Section 2" value="2" open>
    Content for section 2
  </:item>
</.accordion>
```

### Dialog Components

```heex
<!-- Dialog -->
<.dialog id="confirm-dialog">
  <:trigger>
    <.button>Open Dialog</.button>
  </:trigger>
  <:content>
    <:header>
      <:title>Confirm Action</:title>
      <:description>Are you sure?</:description>
    </:header>
    <:body>
      This action cannot be undone.
    </:body>
    <:footer>
      <.button variant="outline">Cancel</.button>
      <.button>Confirm</.button>
    </:footer>
  </:content>
</.dialog>

<!-- Popover -->
<.popover id="info-popover">
  <:trigger>
    <.button variant="ghost">Info</.button>
  </:trigger>
  <:content>
    <p class="text-sm">Additional information</p>
  </:content>
</.popover>

<!-- Tooltip -->
<.tooltip content="Save your changes">
  <.button>Save</.button>
</.tooltip>
```

### Menu Components

```heex
<!-- Dropdown Menu -->
<.dropdown_menu id="actions-menu">
  <:trigger>
    <.button variant="outline">Actions</.button>
  </:trigger>
  <:item phx-click="edit">Edit</:item>
  <:item phx-click="duplicate">Duplicate</:item>
  <:separator />
  <:item phx-click="delete">Delete</:item>
</.dropdown_menu>

<!-- Command Palette -->
<.command id="cmd-palette" placeholder="Search...">
  <:group label="Actions">
    <:item phx-click="new-file">New File</:item>
    <:item phx-click="new-folder">New Folder</:item>
  </:group>
  <:group label="Settings">
    <:item phx-click="preferences">Preferences</:item>
  </:group>
</.command>
```

### Navigation

```heex
<!-- Breadcrumb -->
<.breadcrumb>
  <:item navigate={~p"/"}>Home</:item>
  <:item navigate={~p"/docs"}>Docs</:item>
  <:item>Components</:item>
</.breadcrumb>

<!-- Pagination -->
<.pagination
  current_page={3}
  total_pages={10}
  on_page_change="goto-page"
/>

<!-- Navigation Menu -->
<.navigation_menu>
  <:item navigate={~p"/"} active>Home</:item>
  <:item navigate={~p"/about"}>About</:item>
  <:item navigate={~p"/contact"}>Contact</:item>
</.navigation_menu>
```

### Advanced Components

```heex
<!-- Carousel -->
<.carousel id="hero-carousel" auto_play interval={5000}>
  <:item>
    <img src="/slide1.jpg" alt="Slide 1" />
  </:item>
  <:item>
    <img src="/slide2.jpg" alt="Slide 2" />
  </:item>
</.carousel>

<!-- Table -->
<.table>
  <:header>
    <:column>Name</:column>
    <:column>Email</:column>
    <:column>Role</:column>
  </:header>
  <:row>
    <:cell>John Doe</:cell>
    <:cell>john@example.com</:cell>
    <:cell>Admin</:cell>
  </:row>
</.table>

<!-- Sidebar -->
<.sidebar>
  <:header>
    <h2>App Name</h2>
  </:header>
  <:content>
    <nav><!-- Navigation items --></nav>
  </:content>
  <:footer>
    <p>© 2024</p>
  </:footer>
</.sidebar>
```

## Component Variants

Most components support variants for different use cases:

### Button Variants
- `default` - Standard button
- `primary` - Primary action
- `secondary` - Secondary action
- `outline` - Outlined button
- `ghost` - Minimal styling
- `destructive` - Dangerous actions
- `link` - Link-styled button

### Button Sizes
- `default` - Standard size
- `sm` - Small
- `lg` - Large
- `icon` - Icon-only button
- `icon-sm` - Small icon button
- `icon-lg` - Large icon button

### Alert Variants
- `default` - Standard alert
- `info` - Informational
- `success` - Success message
- `warning` - Warning message
- `error` - Error message

## Accessibility

All components are built with accessibility in mind:

- Proper ARIA attributes
- Keyboard navigation support
- Focus management
- Screen reader compatibility
- Semantic HTML
- Proper contrast ratios

## Customization

### Tailwind Classes

All components accept a `class` attribute for custom styling:

```heex
<.button class="w-full">Full Width Button</.button>
<.card class="max-w-md mx-auto">Centered Card</.card>
```

### Component Variants

Modify the variant functions in each component file to customize default styles:

```elixir
defp variant_classes("primary"),
  do: "bg-blue-600 text-white hover:bg-blue-700"
```

## JavaScript Hooks

Some components require JavaScript hooks for interactivity:

- **Select** - Dropdown handling
- **Slider** - Range input styling
- **InputOTP** - Auto-focus and paste handling
- **Combobox** - Search and filtering
- **Command** - Keyboard navigation
- **ContextMenu** - Right-click handling
- **Carousel** - Slide navigation
- **Resizable** - Panel resizing
- **Toast** - Auto-dismiss

The hooks are automatically registered in `app.js`.

## Browser Support

- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Edge (latest)

## Contributing

Components follow these conventions:

1. **Naming** - PascalCase for modules, snake_case for attributes
2. **Documentation** - Moduledoc with examples
3. **Attributes** - Use `attr` with types and validation
4. **Slots** - Use `slot` for flexible content
5. **Classes** - Use the `classes/1` utility for class merging
6. **Accessibility** - Include ARIA attributes

## License

MIT License - feel free to use in your projects.

## Credits

Inspired by:
- [shadcn/ui](https://ui.shadcn.com/)
- [Base UI](https://base-ui.com/)
- [Radix UI](https://www.radix-ui.com/)

Built for Phoenix LiveView with ❤️
