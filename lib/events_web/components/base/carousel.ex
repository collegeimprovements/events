defmodule EventsWeb.Components.Base.Carousel do
  @moduledoc """
  Carousel component for sliding content.

  ## Examples

      <.carousel id="featured-carousel">
        <:item>
          <img src="/image1.jpg" alt="Slide 1" />
        </:item>
        <:item>
          <img src="/image2.jpg" alt="Slide 2" />
        </:item>
        <:item>
          <img src="/image3.jpg" alt="Slide 3" />
        </:item>
      </.carousel>

      <.carousel id="products" auto_play interval={5000}>
        <:item>Product 1</:item>
        <:item>Product 2</:item>
      </.carousel>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :auto_play, :boolean, default: false
  attr :interval, :integer, default: 3000
  attr :show_controls, :boolean, default: true
  attr :show_indicators, :boolean, default: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :item, required: true

  def carousel(assigns) do
    ~H"""
    <div
      id={@id}
      class={classes(["relative", @class])}
      phx-hook="Carousel"
      data-auto-play={@auto_play}
      data-interval={@interval}
      {@rest}
    >
      <div class="relative overflow-hidden rounded-lg">
        <div class="flex transition-transform duration-500 ease-in-out">
          <%= for {item, index} <- Enum.with_index(@item) do %>
            <div
              class={
                classes([
                  "min-w-full",
                  if(index == 0, do: "block", else: "hidden")
                ])
              }
              data-carousel-item={index}
            >
              <%= render_slot(item) %>
            </div>
          <% end %>
        </div>
      </div>
      <%= if @show_controls do %>
        <button
          type="button"
          phx-click={prev_slide(@id)}
          class="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-white/80 p-2 shadow-md hover:bg-white"
          aria-label="Previous slide"
        >
          <svg
            class="h-6 w-6"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
        <button
          type="button"
          phx-click={next_slide(@id)}
          class="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-white/80 p-2 shadow-md hover:bg-white"
          aria-label="Next slide"
        >
          <svg
            class="h-6 w-6"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
      <% end %>
      <%= if @show_indicators do %>
        <div class="absolute bottom-4 left-1/2 flex -translate-x-1/2 space-x-2">
          <%= for index <- 0..(length(@item) - 1) do %>
            <button
              type="button"
              phx-click={goto_slide(@id, index)}
              class={
                classes([
                  "h-2 w-2 rounded-full",
                  if(index == 0, do: "bg-white", else: "bg-white/50")
                ])
              }
              aria-label={"Go to slide #{index + 1}"}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp prev_slide(_id), do: JS.dispatch("carousel:prev")
  defp next_slide(_id), do: JS.dispatch("carousel:next")
  defp goto_slide(_id, index), do: JS.dispatch("carousel:goto", detail: %{index: index})
end
