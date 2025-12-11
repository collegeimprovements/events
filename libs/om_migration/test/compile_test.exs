defmodule OmMigration.CompileTest do
  @moduledoc """
  Tests that the library compiles without warnings.
  """
  use ExUnit.Case, async: false

  @tag timeout: 60_000
  test "compiles without warnings" do
    {output, exit_code} =
      System.cmd("mix", ["compile", "--warnings-as-errors"],
        stderr_to_stdout: true,
        cd: File.cwd!(),
        env: []
      )

    # Filter out expected info messages
    filtered_output =
      output
      |> String.split("\n")
      |> Enum.reject(fn line ->
        String.contains?(line, "Compiling") or
          String.contains?(line, "Generated") or
          String.contains?(line, "==>") or
          String.contains?(line, "deps.compile") or
          String.trim(line) == ""
      end)
      |> Enum.join("\n")

    assert exit_code == 0,
           """
           Compilation failed with warnings or errors.

           Exit code: #{exit_code}
           Output:
           #{filtered_output}

           Run `mix compile --warnings-as-errors` to see all warnings.
           """
  end
end
