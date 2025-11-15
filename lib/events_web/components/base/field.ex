defmodule EventsWeb.Components.Base.Field do
  @moduledoc """
  Field component combining label, input, and help text.

  ## Examples

      <.field name="email" label="Email" type="email" />

      <.field name="password" label="Password" type="password" required>
        <:description>Must be at least 8 characters</:description>
      </.field>

      <.field name="bio" label="Bio">
        <:input>
          <.textarea name="bio" />
        </:input>
        <:description>Tell us about yourself</:description>
      </.field>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  import EventsWeb.Components.Base.Label
  import EventsWeb.Components.Base.Input

  attr :name, :string, required: true
  attr :label, :string, default: nil
  attr :type, :string, default: "text"
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :description
  slot :input

  def field(assigns) do
    ~H"""
    <div class={classes(["space-y-2", @class])} {@rest}>
      <.label :if={@label} for={@name} required={@required}>
        <%= @label %>
      </.label>
      <%= if @input != [] do %>
        <%= render_slot(@input) %>
      <% else %>
        <.input
          name={@name}
          type={@type}
          value={@value}
          placeholder={@placeholder}
          disabled={@disabled}
          error={@error}
        />
      <% end %>
      <p :if={@description != []} class="text-xs text-zinc-500">
        <%= render_slot(@description) %>
      </p>
    </div>
    """
  end
end
