defmodule EventsWeb.Components.Base.ToggleGroup do
  @moduledoc """
  ToggleGroup component for grouped toggle buttons.

  ## Examples

      <.toggle_group type="single" name="alignment">
        <:item value="left">Left</:item>
        <:item value="center">Center</:item>
        <:item value="right">Right</:item>
      </.toggle_group>

      <.toggle_group type="multiple" name="formatting">
        <:item value="bold">Bold</:item>
        <:item value="italic">Italic</:item>
        <:item value="underline">Underline</:item>
      </.toggle_group>
  """
  use Phoenix.Component
  import EventsWeb.Components.Base, only: [classes: 1]

  attr :type, :string, default: "single", values: ~w(single multiple)
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :variant, :string, default: "default", values: ~w(default outline)
  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :item, required: true do
    attr :value, :string, required: true
  end

  def toggle_group(assigns) do
    ~H"""
    <div
      role="group"
      class={
        classes([
          "inline-flex rounded-md shadow-sm",
          @class
        ])
      }
      {@rest}
    >
      <%= for {item, index} <- Enum.with_index(@item) do %>
        <button
          type="button"
          role={if @type == "single", do: "radio", else: "checkbox"}
          aria-pressed={to_string(is_selected?(@value, item.value, @type))}
          phx-click="toggle-group-select"
          phx-value-name={@name}
          phx-value-item={item.value}
          class={
            classes([
              "inline-flex items-center justify-center px-3 font-medium",
              "transition-colors duration-150",
              "focus:z-10 focus:outline-none focus:ring-2 focus:ring-zinc-950",
              size_classes(@size),
              variant_classes(@variant, is_selected?(@value, item.value, @type)),
              rounded_classes(index, length(@item))
            ])
          }
        >
          <%= render_slot(item) %>
        </button>
      <% end %>
    </div>
    """
  end

  defp is_selected?(value, item_value, "single"), do: value == item_value

  defp is_selected?(value, item_value, "multiple") when is_list(value),
    do: item_value in value

  defp is_selected?(_, _, _), do: false

  defp variant_classes("default", false),
    do: "bg-white border border-zinc-300 hover:bg-zinc-100 hover:text-zinc-900"

  defp variant_classes("default", true),
    do: "bg-zinc-100 border border-zinc-300 text-zinc-900"

  defp variant_classes("outline", false),
    do: "border border-zinc-300 bg-transparent hover:bg-zinc-100 hover:text-zinc-900"

  defp variant_classes("outline", true),
    do: "border border-zinc-300 bg-zinc-100 text-zinc-900"

  defp size_classes("default"), do: "h-10 text-sm"
  defp size_classes("sm"), do: "h-8 text-xs"
  defp size_classes("lg"), do: "h-12 text-base"

  defp rounded_classes(0, _total), do: "rounded-l-md"
  defp rounded_classes(index, total) when index == total - 1, do: "rounded-r-md -ml-px"
  defp rounded_classes(_, _), do: "-ml-px"
end
