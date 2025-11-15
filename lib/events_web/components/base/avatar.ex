defmodule EventsWeb.Components.Base.Avatar do
  @moduledoc """
  Avatar component for displaying user profile images with fallback support.

  ## Examples

      <.avatar src="/images/user.jpg" alt="John Doe" />
      <.avatar fallback="JD" />
      <.avatar size="lg">
        <img src="/images/user.jpg" alt="User" />
      </.avatar>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :src, :string, default: nil
  attr :alt, :string, default: ""
  attr :fallback, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default sm lg xl)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block

  def avatar(assigns) do
    ~H"""
    <div
      class={
        classes([
          "relative inline-flex shrink-0 overflow-hidden rounded-full",
          "bg-zinc-100 text-zinc-900",
          size_classes(@size),
          @class
        ])
      }
      {@rest}
    >
      <%= if @inner_block != [] do %>
        <%= render_slot(@inner_block) %>
      <% else %>
        <%= if @src do %>
          <img src={@src} alt={@alt} class="aspect-square h-full w-full object-cover" />
        <% else %>
          <span class={
            classes([
              "flex h-full w-full items-center justify-center",
              "bg-zinc-200 font-medium text-zinc-700",
              fallback_text_size(@size)
            ])
          }>
            <%= @fallback || extract_initials(@alt) %>
          </span>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp size_classes("default"), do: "h-10 w-10"
  defp size_classes("sm"), do: "h-8 w-8"
  defp size_classes("lg"), do: "h-12 w-12"
  defp size_classes("xl"), do: "h-16 w-16"

  defp fallback_text_size("sm"), do: "text-xs"
  defp fallback_text_size("default"), do: "text-sm"
  defp fallback_text_size("lg"), do: "text-base"
  defp fallback_text_size("xl"), do: "text-xl"

  defp extract_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp extract_initials(_), do: "?"
end
