defmodule Events.Services.Typst do
  @moduledoc """
  Typst document compilation service.

  Thin wrapper around `OmTypst` with Events-specific defaults.

  See `OmTypst` for full documentation.
  """

  # Compile
  defdelegate compile(input_path, opts \\ []), to: OmTypst
  defdelegate compile!(input_path, opts \\ []), to: OmTypst
  defdelegate compile_string(content, opts \\ []), to: OmTypst
  defdelegate compile_string!(content, opts \\ []), to: OmTypst
  defdelegate stream!(input_path, opts \\ []), to: OmTypst
  defdelegate stream(input_path, opts \\ []), to: OmTypst
  defdelegate stream_string!(content, opts \\ []), to: OmTypst

  # Watch
  defdelegate watch(input_path, output_path, opts \\ []), to: OmTypst
  defdelegate stop_watch(task), to: OmTypst

  # Query
  defdelegate query(input_path, selector, opts \\ []), to: OmTypst
  defdelegate query!(input_path, selector, opts \\ []), to: OmTypst

  # Fonts
  defdelegate fonts(opts \\ []), to: OmTypst
  defdelegate fonts!(opts \\ []), to: OmTypst

  # Init
  defdelegate init(template, path \\ nil, opts \\ []), to: OmTypst

  # Utility
  defdelegate available?(), to: OmTypst
  defdelegate version(), to: OmTypst
  defdelegate version!(), to: OmTypst
end
