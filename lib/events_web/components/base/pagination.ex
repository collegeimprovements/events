defmodule EventsWeb.Components.Base.Pagination do
  @moduledoc """
  Pagination component for navigating pages.

  ## Examples

      <.pagination current_page={1} total_pages={10} />
      <.pagination current_page={5} total_pages={20} sibling_count={2} />
      <.pagination
        current_page={3}
        total_pages={15}
        on_page_change="goto-page"
      />
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :current_page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :sibling_count, :integer, default: 1
  attr :on_page_change, :string, default: "page-change"
  attr :class, :string, default: nil
  attr :rest, :global

  def pagination(assigns) do
    assigns = assign(assigns, :pages, generate_pages(assigns.current_page, assigns.total_pages, assigns.sibling_count))

    ~H"""
    <nav
      role="navigation"
      aria-label="Pagination"
      class={classes(["flex items-center justify-center space-x-2", @class])}
      {@rest}
    >
      <button
        type="button"
        phx-click={@on_page_change}
        phx-value-page={max(@current_page - 1, 1)}
        disabled={@current_page == 1}
        class={
          classes([
            "inline-flex h-10 items-center justify-center rounded-md px-4 py-2",
            "text-sm font-medium transition-colors",
            "hover:bg-zinc-100 focus:bg-zinc-100 focus:outline-none",
            "disabled:pointer-events-none disabled:opacity-50"
          ])
        }
        aria-label="Previous page"
      >
        Previous
      </button>
      <%= for page <- @pages do %>
        <%= if page == :ellipsis do %>
          <span class="px-4 py-2 text-sm">...</span>
        <% else %>
          <button
            type="button"
            phx-click={@on_page_change}
            phx-value-page={page}
            aria-current={if page == @current_page, do: "page", else: nil}
            class={
              classes([
                "inline-flex h-10 w-10 items-center justify-center rounded-md",
                "text-sm font-medium transition-colors",
                "focus:outline-none focus:ring-2 focus:ring-zinc-950 focus:ring-offset-2",
                if(page == @current_page,
                  do: "bg-zinc-900 text-zinc-50 hover:bg-zinc-800",
                  else: "hover:bg-zinc-100 focus:bg-zinc-100"
                )
              ])
            }
          >
            <%= page %>
          </button>
        <% end %>
      <% end %>
      <button
        type="button"
        phx-click={@on_page_change}
        phx-value-page={min(@current_page + 1, @total_pages)}
        disabled={@current_page == @total_pages}
        class={
          classes([
            "inline-flex h-10 items-center justify-center rounded-md px-4 py-2",
            "text-sm font-medium transition-colors",
            "hover:bg-zinc-100 focus:bg-zinc-100 focus:outline-none",
            "disabled:pointer-events-none disabled:opacity-50"
          ])
        }
        aria-label="Next page"
      >
        Next
      </button>
    </nav>
    """
  end

  defp generate_pages(current, total, sibling_count) do
    left_sibling = max(current - sibling_count, 1)
    right_sibling = min(current + sibling_count, total)

    show_left_ellipsis = left_sibling > 2
    show_right_ellipsis = right_sibling < total - 1

    cond do
      !show_left_ellipsis && show_right_ellipsis ->
        Enum.to_list(1..min(3 + 2 * sibling_count, total)) ++ [:ellipsis, total]

      show_left_ellipsis && !show_right_ellipsis ->
        [1, :ellipsis] ++ Enum.to_list(max(total - (2 + 2 * sibling_count), 1)..total)

      show_left_ellipsis && show_right_ellipsis ->
        [1, :ellipsis] ++ Enum.to_list(left_sibling..right_sibling) ++ [:ellipsis, total]

      true ->
        Enum.to_list(1..total)
    end
  end
end
