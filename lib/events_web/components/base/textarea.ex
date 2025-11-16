defmodule EventsWeb.Components.Base.Textarea do
  @moduledoc """
  Textarea component for multi-line text input.

  ## Examples

      <.textarea name="description" placeholder="Enter description" />
      <.textarea name="bio" rows={10} />
      <.textarea name="comment" error="Comment is required" />
  """
  use Phoenix.Component
  alias EventsWeb.Components.Base.Utils

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :rows, :integer, default: 4
  attr :class, :string, default: nil

  attr :rest, :global,
    include:
      ~w(autocomplete cols dirname maxlength minlength readonly required spellcheck wrap)

  def textarea(assigns) do
    ~H"""
    <div class="w-full">
      <textarea
        name={@name}
        placeholder={@placeholder}
        disabled={@disabled}
        rows={@rows}
        aria-invalid={to_string(!!@error)}
        aria-describedby={error_id(@error, @name)}
        class={textarea_classes(@error, @class)}
        {@rest}
      ><%= @value %></textarea>
      <p :if={@error} id={"#{@name}-error"} class="mt-1 text-xs text-red-600">
        <%= @error %>
      </p>
    </div>
    """
  end

  defp textarea_classes(error, custom_class) do
    [
      "flex w-full rounded-md border bg-white px-3 py-2",
      "text-sm text-zinc-900 placeholder:text-zinc-500",
      "transition-colors duration-150",
      "focus:outline-none focus:ring-2 focus:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50 resize-y",
      error_state_classes(error),
      custom_class
    ]
    |> Utils.classes()
  end

  defp error_state_classes(nil), do: "border-zinc-300 focus:ring-zinc-950"
  defp error_state_classes(_), do: "border-red-500 focus:ring-red-500"

  defp error_id(nil, _), do: nil
  defp error_id(_, name), do: "#{name}-error"
end
