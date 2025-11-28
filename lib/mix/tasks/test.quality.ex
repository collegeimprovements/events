defmodule Mix.Tasks.Test.Quality do
  @moduledoc """
  Runs comprehensive test suite quality checks.

  This task validates:
  1. Code formatting (`mix format --check-formatted`)
  2. No compile warnings (`mix compile --warnings-as-errors`)
  3. Static analysis (`mix credo --strict`)
  4. All tests pass (`mix test --warnings-as-errors`)
  5. No unused dependencies (`mix deps.unlock --check-unused`)

  ## Usage

      mix test.quality

  ## Options

      --skip-format     Skip format check
      --skip-credo      Skip Credo analysis
      --skip-deps       Skip unused deps check
      --verbose         Show detailed output
      --fail-fast       Stop on first failure

  ## Exit Codes

      0 - All checks passed
      1 - One or more checks failed
  """

  use Mix.Task

  @shortdoc "Run comprehensive test quality checks"

  @switches [
    skip_format: :boolean,
    skip_credo: :boolean,
    skip_deps: :boolean,
    verbose: :boolean,
    fail_fast: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    verbose = Keyword.get(opts, :verbose, false)
    fail_fast = Keyword.get(opts, :fail_fast, false)

    checks = build_checks(opts)

    IO.puts("\n#{IO.ANSI.cyan()}━━━ Test Quality Checks ━━━#{IO.ANSI.reset()}\n")

    results =
      Enum.reduce_while(checks, [], fn {name, check_fn}, acc ->
        IO.write("  #{name}... ")

        case run_check(check_fn, verbose) do
          :ok ->
            IO.puts("#{IO.ANSI.green()}✓#{IO.ANSI.reset()}")
            {:cont, [{name, :ok} | acc]}

          {:error, output} ->
            IO.puts("#{IO.ANSI.red()}✗#{IO.ANSI.reset()}")

            if verbose do
              IO.puts("\n#{IO.ANSI.yellow()}#{output}#{IO.ANSI.reset()}\n")
            end

            if fail_fast do
              {:halt, [{name, {:error, output}} | acc]}
            else
              {:cont, [{name, {:error, output}} | acc]}
            end
        end
      end)

    print_summary(Enum.reverse(results))

    failures = Enum.filter(results, fn {_, result} -> result != :ok end)

    if failures == [] do
      IO.puts("\n#{IO.ANSI.green()}All quality checks passed!#{IO.ANSI.reset()}\n")
      System.halt(0)
    else
      IO.puts("\n#{IO.ANSI.red()}#{length(failures)} check(s) failed#{IO.ANSI.reset()}\n")
      System.halt(1)
    end
  end

  defp build_checks(opts) do
    checks = []

    checks =
      if Keyword.get(opts, :skip_deps, false) do
        checks
      else
        checks ++ [{"Unused dependencies", &check_unused_deps/0}]
      end

    checks =
      if Keyword.get(opts, :skip_format, false) do
        checks
      else
        checks ++ [{"Code formatting", &check_format/0}]
      end

    checks = checks ++ [{"Compilation (warnings as errors)", &check_compile/0}]

    checks =
      if Keyword.get(opts, :skip_credo, false) do
        checks
      else
        checks ++ [{"Static analysis (Credo)", &check_credo/0}]
      end

    checks ++ [{"Tests", &check_tests/0}]
  end

  defp run_check(check_fn, _verbose) do
    check_fn.()
  end

  defp check_unused_deps do
    case System.cmd("mix", ["deps.unlock", "--check-unused"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp check_format do
    case System.cmd("mix", ["format", "--check-formatted"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp check_compile do
    case System.cmd("mix", ["compile", "--warnings-as-errors", "--force"],
           stderr_to_stdout: true,
           env: [{"MIX_ENV", "test"}]
         ) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp check_credo do
    case System.cmd("mix", ["credo", "--strict"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp check_tests do
    case System.cmd("mix", ["test", "--warnings-as-errors"],
           stderr_to_stdout: true,
           env: [{"MIX_ENV", "test"}]
         ) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp print_summary(results) do
    IO.puts("\n#{IO.ANSI.cyan()}━━━ Summary ━━━#{IO.ANSI.reset()}\n")

    Enum.each(results, fn {name, result} ->
      status =
        case result do
          :ok -> "#{IO.ANSI.green()}PASS#{IO.ANSI.reset()}"
          {:error, _} -> "#{IO.ANSI.red()}FAIL#{IO.ANSI.reset()}"
        end

      IO.puts("  #{String.pad_trailing(name, 35)} #{status}")
    end)
  end
end
