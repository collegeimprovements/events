defmodule EventsWeb.Components.Base.Typography do
  @moduledoc """
  Typography components for consistent text styling.

  ## Examples

      <.typography variant="h1">Heading 1</.typography>
      <.typography variant="h2">Heading 2</.typography>
      <.typography variant="p">Paragraph text</.typography>
      <.typography variant="lead">Lead paragraph</.typography>
      <.typography variant="muted">Muted text</.typography>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :variant, :string,
    default: "p",
    values: ~w(h1 h2 h3 h4 h5 h6 p lead large small muted code)

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def typography(assigns) do
    ~H"""
    <%= case @variant do %>
      <% "h1" -> %>
        <h1
          class={
            classes([
              "scroll-m-20 text-4xl font-extrabold tracking-tight lg:text-5xl",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </h1>
      <% "h2" -> %>
        <h2
          class={
            classes([
              "scroll-m-20 border-b pb-2 text-3xl font-semibold tracking-tight first:mt-0",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </h2>
      <% "h3" -> %>
        <h3
          class={
            classes([
              "scroll-m-20 text-2xl font-semibold tracking-tight",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </h3>
      <% "h4" -> %>
        <h4
          class={
            classes([
              "scroll-m-20 text-xl font-semibold tracking-tight",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </h4>
      <% "h5" -> %>
        <h5
          class={
            classes([
              "scroll-m-20 text-lg font-semibold tracking-tight",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </h5>
      <% "h6" -> %>
        <h6
          class={
            classes([
              "scroll-m-20 text-base font-semibold tracking-tight",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </h6>
      <% "p" -> %>
        <p
          class={
            classes([
              "leading-7 [&:not(:first-child)]:mt-6",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </p>
      <% "lead" -> %>
        <p
          class={
            classes([
              "text-xl text-zinc-700",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </p>
      <% "large" -> %>
        <div
          class={
            classes([
              "text-lg font-semibold",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </div>
      <% "small" -> %>
        <small
          class={
            classes([
              "text-sm font-medium leading-none",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </small>
      <% "muted" -> %>
        <p
          class={
            classes([
              "text-sm text-zinc-500",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </p>
      <% "code" -> %>
        <code
          class={
            classes([
              "relative rounded bg-zinc-100 px-[0.3rem] py-[0.2rem]",
              "font-mono text-sm font-semibold text-zinc-900",
              @class
            ])
          }
          {@rest}
        >
          <%= render_slot(@inner_block) %>
        </code>
    <% end %>
    """
  end
end
