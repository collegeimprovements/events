defmodule EventsWeb.Components.Base.Utils do
  @moduledoc """
  Shared utilities for Base UI components.

  Provides common functionality for:
  - Class name merging and management
  - Variant systems
  - Size systems
  - Positioning utilities
  - Common patterns
  """

  @doc """
  Merges multiple class lists into a single string, handling nil values and deduplication.

  ## Examples

      iex> classes(["bg-red-500", "text-white", nil, "rounded"])
      "bg-red-500 text-white rounded"

      iex> classes("bg-blue-500 hover:bg-blue-600")
      "bg-blue-500 hover:bg-blue-600"
  """
  def classes(class_list) when is_list(class_list) do
    class_list
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.trim()
    |> dedupe_classes()
  end

  def classes(class) when is_binary(class), do: String.trim(class)
  def classes(nil), do: ""

  @doc """
  Deduplicates Tailwind classes, keeping the last occurrence.
  This is useful when merging classes where later values should override earlier ones.
  """
  def dedupe_classes(class_string) when is_binary(class_string) do
    class_string
    |> String.split(" ")
    |> Enum.reverse()
    |> Enum.uniq_by(&extract_class_prefix/1)
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp extract_class_prefix(class) do
    # Extract the base class without modifiers
    class
    |> String.split(":")
    |> List.last()
    |> String.replace(~r/^-/, "")
    |> String.split("-")
    |> Enum.take(2)
    |> Enum.join("-")
  end

  @doc """
  Gets variant classes from a variants map.

  ## Examples

      iex> variants = %{"primary" => "bg-blue-600", "secondary" => "bg-gray-600"}
      iex> variant("primary", variants)
      "bg-blue-600"
  """
  def variant(key, variants, default \\ "")
  def variant(key, variants, default) when is_map(variants), do: Map.get(variants, key, default)
  def variant(_, _, default), do: default

  @doc """
  Standard button variants used across button-like components.
  """
  def button_variants do
    %{
      "default" => "bg-zinc-900 text-zinc-50 shadow hover:bg-zinc-800 focus-visible:ring-zinc-950",
      "primary" => "bg-blue-600 text-white shadow hover:bg-blue-700 focus-visible:ring-blue-600",
      "secondary" => "bg-zinc-100 text-zinc-900 shadow-sm hover:bg-zinc-200 focus-visible:ring-zinc-500",
      "outline" => "border border-zinc-300 bg-white text-zinc-900 shadow-sm hover:bg-zinc-50 focus-visible:ring-zinc-500",
      "ghost" => "text-zinc-900 hover:bg-zinc-100 focus-visible:ring-zinc-500",
      "destructive" => "bg-red-600 text-white shadow hover:bg-red-700 focus-visible:ring-red-600",
      "link" => "text-zinc-900 underline-offset-4 hover:underline"
    }
  end

  @doc """
  Standard size variants used across components.
  """
  def size_variants do
    %{
      "sm" => "h-8 px-3 py-1 text-xs rounded",
      "default" => "h-10 px-4 py-2 text-sm",
      "lg" => "h-12 px-6 py-3 text-base",
      "icon" => "h-10 w-10 p-0",
      "icon-sm" => "h-8 w-8 p-0",
      "icon-lg" => "h-12 w-12 p-0"
    }
  end

  @doc """
  Alert/status variants used across alert, badge, toast components.
  """
  def status_variants do
    %{
      "default" => %{
        bg: "bg-white",
        text: "text-zinc-900",
        border: "border-zinc-200"
      },
      "info" => %{
        bg: "bg-blue-50",
        text: "text-blue-900",
        border: "border-blue-200"
      },
      "success" => %{
        bg: "bg-green-50",
        text: "text-green-900",
        border: "border-green-200"
      },
      "warning" => %{
        bg: "bg-yellow-50",
        text: "text-yellow-900",
        border: "border-yellow-200"
      },
      "error" => %{
        bg: "bg-red-50",
        text: "text-red-900",
        border: "border-red-200"
      }
    }
  end

  @doc """
  Badge variants for compact status indicators.
  """
  def badge_variants do
    %{
      "default" => "bg-zinc-900 text-zinc-50 hover:bg-zinc-800",
      "success" => "bg-green-100 text-green-800 hover:bg-green-200",
      "warning" => "bg-yellow-100 text-yellow-800 hover:bg-yellow-200",
      "error" => "bg-red-100 text-red-800 hover:bg-red-200",
      "info" => "bg-blue-100 text-blue-800 hover:bg-blue-200",
      "outline" => "border border-zinc-300 bg-white text-zinc-900 hover:bg-zinc-50",
      "secondary" => "bg-zinc-100 text-zinc-900 hover:bg-zinc-200"
    }
  end

  @doc """
  Common base classes for interactive elements.
  """
  def interactive_base do
    [
      "inline-flex items-center justify-center",
      "rounded-md font-medium",
      "transition-colors duration-150",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2",
      "disabled:pointer-events-none disabled:opacity-50"
    ]
  end

  @doc """
  Common base classes for input elements.
  """
  def input_base do
    [
      "flex w-full rounded-md border bg-white px-3 py-2",
      "text-sm text-zinc-900 placeholder:text-zinc-500",
      "transition-colors duration-150",
      "focus:outline-none focus:ring-2 focus:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50"
    ]
  end

  @doc """
  Common base classes for overlay/popup components.
  """
  def overlay_base do
    [
      "fixed inset-0 z-50",
      "bg-black/50",
      "flex items-center justify-center"
    ]
  end

  @doc """
  Common base classes for floating/positioned elements.
  """
  def floating_base do
    [
      "absolute z-50",
      "rounded-md border border-zinc-200 bg-white shadow-lg",
      "animate-in fade-in-0 zoom-in-95"
    ]
  end

  @doc """
  Returns position classes for floating elements.

  ## Examples

      iex> position_classes("top", "center")
      "bottom-full left-1/2 -translate-x-1/2 mb-2"
  """
  def position_classes(side, align \\ "center")

  def position_classes("top", "center"), do: "bottom-full left-1/2 -translate-x-1/2 mb-2"
  def position_classes("top", "start"), do: "bottom-full left-0 mb-2"
  def position_classes("top", "end"), do: "bottom-full right-0 mb-2"
  def position_classes("bottom", "center"), do: "top-full left-1/2 -translate-x-1/2 mt-2"
  def position_classes("bottom", "start"), do: "top-full left-0 mt-2"
  def position_classes("bottom", "end"), do: "top-full right-0 mt-2"
  def position_classes("left", "center"), do: "right-full top-1/2 -translate-y-1/2 mr-2"
  def position_classes("left", "start"), do: "right-full top-0 mr-2"
  def position_classes("left", "end"), do: "right-full bottom-0 mr-2"
  def position_classes("right", "center"), do: "left-full top-1/2 -translate-y-1/2 ml-2"
  def position_classes("right", "start"), do: "left-full top-0 ml-2"
  def position_classes("right", "end"), do: "left-full bottom-0 ml-2"
  def position_classes(_, _), do: "top-full left-1/2 -translate-x-1/2 mt-2"

  @doc """
  Animation classes for enter/exit transitions.
  """
  def animation_in do
    "animate-in fade-in-0 zoom-in-95 duration-200"
  end

  def animation_out do
    "animate-out fade-out-0 zoom-out-95 duration-150"
  end

  @doc """
  Common menu item classes.
  """
  def menu_item_base do
    [
      "relative flex cursor-pointer select-none items-center",
      "rounded-sm px-2 py-1.5 text-sm outline-none",
      "transition-colors",
      "hover:bg-zinc-100 focus:bg-zinc-100",
      "disabled:pointer-events-none disabled:opacity-50"
    ]
  end

  @doc """
  Generates a random ID with a prefix.
  """
  def generate_id(prefix \\ "base") do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  @doc """
  Extracts initials from a name string.

  ## Examples

      iex> extract_initials("John Doe")
      "JD"

      iex> extract_initials("Alice")
      "A"
  """
  def extract_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  def extract_initials(_), do: "?"

  @doc """
  Formats a date for display.
  """
  def format_date(nil), do: nil
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")
  def format_date(date) when is_binary(date), do: date

  @doc """
  Calculates percentage for progress bars.
  """
  def calculate_percentage(value, max) when max > 0 do
    min(round(value / max * 100), 100)
  end

  def calculate_percentage(_, _), do: 0
end
