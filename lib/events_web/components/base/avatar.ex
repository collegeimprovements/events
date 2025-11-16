defmodule EventsWeb.Components.Base.Avatar do
  @moduledoc """
  Avatar component for displaying user profile images with fallback support.

  Uses shared utilities for consistent sizing and initials extraction.

  ## Examples

      <.avatar src="/images/user.jpg" alt="John Doe" />
      <.avatar fallback="JD" />
      <.avatar size="lg">
        <img src="/images/user.jpg" alt="User" />
      </.avatar>
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  @size_map %{
    "sm" => %{container: "h-8 w-8", text: "text-xs"},
    "default" => %{container: "h-10 w-10", text: "text-sm"},
    "lg" => %{container: "h-12 w-12", text: "text-base"},
    "xl" => %{container: "h-16 w-16", text: "text-xl"}
  }

  attr :src, :string, default: nil
  attr :alt, :string, default: ""
  attr :fallback, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default sm lg xl)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block

  def avatar(%{inner_block: [_ | _]} = assigns) do
    ~H"""
    <div class={container_classes(@size, @class)} {@rest}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def avatar(%{src: src} = assigns) when is_binary(src) do
    ~H"""
    <div class={container_classes(@size, @class)} {@rest}>
      <img src={@src} alt={@alt} class="aspect-square h-full w-full object-cover" />
    </div>
    """
  end

  def avatar(assigns) do
    assigns = assign(assigns, :initials, assigns.fallback || Utils.extract_initials(assigns.alt))

    ~H"""
    <div class={container_classes(@size, @class)} {@rest}>
      <span class={fallback_classes(@size)}>
        <%= @initials %>
      </span>
    </div>
    """
  end

  defp container_classes(size, custom_class) do
    @size_map
    |> Map.get(size, @size_map["default"])
    |> Map.get(:container)
    |> then(&Utils.classes([
      "relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full",
      "bg-zinc-100 text-zinc-900",
      &1,
      custom_class
    ]))
  end

  defp fallback_classes(size) do
    @size_map
    |> Map.get(size, @size_map["default"])
    |> Map.get(:text)
    |> then(&Utils.classes([
      "flex h-full w-full items-center justify-center",
      "bg-zinc-200 font-medium text-zinc-700",
      &1
    ]))
  end
end
