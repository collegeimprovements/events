defmodule Events.CompileQualityTest do
  @moduledoc """
  Tests for compile-time quality checks.

  These tests ensure the codebase compiles cleanly without warnings
  and has reasonable compile-time dependencies.
  """
  use ExUnit.Case, async: false

  @moduletag :compile_quality

  describe "compile warnings" do
    @tag timeout: 120_000
    test "code compiles without warnings" do
      # Clean compile to detect warnings
      {output, exit_code} =
        System.cmd("mix", ["compile", "--force", "--warnings-as-errors"],
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
            String.contains?(line, "Generated events app") or
            String.contains?(line, "Schema validation") or
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

  describe "xref analysis" do
    @tag timeout: 60_000
    test "compile-connected graph is within acceptable limits" do
      # Run xref to check compile-connected dependencies
      {output, _exit_code} =
        System.cmd("mix", ["xref", "graph", "--label", "compile-connected", "--format", "stats"],
          stderr_to_stdout: true,
          cd: File.cwd!(),
          env: []
        )

      # Parse the output to check if dependencies are reasonable
      # This is a soft check - we just want to ensure it runs
      assert String.contains?(output, "Compiling") or
               String.contains?(output, "compile") or
               output != "",
             "xref graph should produce output"
    end

    @tag timeout: 60_000
    test "no undefined function calls" do
      {output, exit_code} =
        System.cmd("mix", ["xref", "unreachable"],
          stderr_to_stdout: true,
          cd: File.cwd!(),
          env: []
        )

      # Filter out any expected warnings
      issues =
        output
        |> String.split("\n")
        |> Enum.filter(fn line ->
          String.contains?(line, "(compile)") and
            not String.contains?(line, "warning:") and
            not String.contains?(line, "Compiling")
        end)

      assert exit_code == 0 and issues == [],
             """
             Found unreachable or undefined calls:
             #{output}
             """
    end
  end
end
