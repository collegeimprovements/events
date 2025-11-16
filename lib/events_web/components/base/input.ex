defmodule EventsWeb.Components.Base.Input do
  @moduledoc """
  Input component for form text entry.

  Uses shared input utilities for consistency across form components.

  ## Examples

      <.input type="text" name="email" placeholder="Enter email" />
      <.input type="password" name="password" required />
      <.input type="email" name="email" error="Invalid email" />
      <.input type="number" name="age" min="0" max="120" />
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  @size_map %{
    "sm" => "h-8 text-xs",
    "default" => "h-10",
    "lg" => "h-12 text-base"
  }

  attr :type, :string, default: "text"
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default sm lg)
  attr :class, :string, default: nil

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols dirname inputmode list max maxlength min minlength
         multiple pattern readonly required rows spellcheck step)

  def input(assigns) do
    assigns = assign(assigns, :error_id, error_id(assigns))

    ~H"""
    <div class="w-full">
      <input
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        disabled={@disabled}
        aria-invalid={to_string(not is_nil(@error))}
        aria-describedby={@error_id}
        class={input_classes(@size, @error, @class)}
        {@rest}
      />
      <p :if={@error} id={@error_id} class="mt-1 text-xs text-red-600">
        <%= @error %>
      </p>
    </div>
    """
  end

  defp input_classes(size, error, custom_class) do
    [
      Utils.input_base(),
      error_state_classes(error),
      Map.get(@size_map, size, @size_map["default"]),
      custom_class
    ]
    |> Utils.classes()
  end

  defp error_state_classes(nil), do: "border-zinc-300 focus:ring-zinc-950"
  defp error_state_classes(_), do: "border-red-500 focus:ring-red-500"

  defp error_id(%{error: nil}), do: nil
  defp error_id(%{name: name}), do: "#{name}-error"
end
