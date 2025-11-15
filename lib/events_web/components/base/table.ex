defmodule EventsWeb.Components.Base.Table do
  @moduledoc """
  Table component for displaying tabular data.

  ## Examples

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
        <:row>
          <:cell>Jane Smith</:cell>
          <:cell>jane@example.com</:cell>
          <:cell>User</:cell>
        </:row>
      </.table>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :class, :string, default: nil
  attr :rest, :global

  slot :header, required: false do
    slot :column
  end

  slot :row, required: true do
    slot :cell
  end

  slot :footer do
    slot :cell
  end

  def table(assigns) do
    ~H"""
    <div class="relative w-full overflow-auto">
      <table class={classes(["w-full caption-bottom text-sm", @class])} {@rest}>
        <thead :if={@header != []} class="border-b border-zinc-200">
          <%= for header <- @header do %>
            <tr class="border-b border-zinc-200 transition-colors hover:bg-zinc-50">
              <%= for column <- header[:column] || [] do %>
                <th class="h-12 px-4 text-left align-middle font-medium text-zinc-500">
                  <%= render_slot(column) %>
                </th>
              <% end %>
            </tr>
          <% end %>
        </thead>
        <tbody class="[&_tr:last-child]:border-0">
          <%= for row <- @row do %>
            <tr class="border-b border-zinc-200 transition-colors hover:bg-zinc-50">
              <%= for cell <- row[:cell] || [] do %>
                <td class="p-4 align-middle">
                  <%= render_slot(cell) %>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
        <tfoot :if={@footer != []} class="border-t border-zinc-200 bg-zinc-50 font-medium">
          <%= for footer <- @footer do %>
            <tr>
              <%= for cell <- footer[:cell] || [] do %>
                <td class="p-4 align-middle">
                  <%= render_slot(cell) %>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tfoot>
      </table>
    </div>
    """
  end
end
