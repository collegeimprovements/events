defmodule Mix.Tasks.Test.Libs do
  @moduledoc """
  Runs tests for all libraries in the libs/ directory.

  ## Usage

      mix test.libs              # Run tests for all libs
      mix test.libs fn_types     # Run tests for specific lib(s)
      mix test.libs --parallel   # Run all lib tests in parallel
      mix test.libs --fail-fast  # Stop on first failure

  ## Options

    * `--parallel` - Run tests for all libs concurrently
    * `--fail-fast` - Stop on first lib test failure
    * `--verbose` - Show detailed output
    * `--quiet` - Only show failures

  """
  use Mix.Task

  @shortdoc "Runs tests for all libraries in libs/"

  @switches [
    parallel: :boolean,
    fail_fast: :boolean,
    verbose: :boolean,
    quiet: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, libs, _} = OptionParser.parse(args, switches: @switches)

    libs_dir = Path.join(File.cwd!(), "libs")

    all_libs =
      libs_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(libs_dir, &1)))
      |> Enum.sort()

    libs_to_test =
      case libs do
        [] -> all_libs
        specified -> Enum.filter(specified, &(&1 in all_libs))
      end

    if libs_to_test == [] do
      Mix.shell().error("No matching libs found in libs/")
      exit({:shutdown, 1})
    end

    Mix.shell().info(
      "\n#{IO.ANSI.cyan()}Testing #{length(libs_to_test)} libs...#{IO.ANSI.reset()}\n"
    )

    results =
      if opts[:parallel] do
        run_parallel(libs_to_test, libs_dir, opts)
      else
        run_sequential(libs_to_test, libs_dir, opts)
      end

    print_summary(results, opts)

    failed = Enum.filter(results, fn {_, status} -> status != :ok end)

    if failed != [] do
      exit({:shutdown, 1})
    end
  end

  defp run_sequential(libs, libs_dir, opts) do
    Enum.reduce_while(libs, [], fn lib, acc ->
      result = run_lib_tests(lib, libs_dir, opts)

      if opts[:fail_fast] && result != :ok do
        {:halt, [{lib, result} | acc]}
      else
        {:cont, [{lib, result} | acc]}
      end
    end)
    |> Enum.reverse()
  end

  defp run_parallel(libs, libs_dir, opts) do
    libs
    |> Task.async_stream(
      fn lib -> {lib, run_lib_tests(lib, libs_dir, opts)} end,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.sort_by(fn {lib, _} -> lib end)
  end

  defp run_lib_tests(lib, libs_dir, opts) do
    lib_path = Path.join(libs_dir, lib)

    unless opts[:quiet] do
      Mix.shell().info("#{IO.ANSI.blue()}▶ Testing #{lib}...#{IO.ANSI.reset()}")
    end

    # Check if mix.exs exists
    unless File.exists?(Path.join(lib_path, "mix.exs")) do
      Mix.shell().error("  #{IO.ANSI.yellow()}⚠ No mix.exs found, skipping#{IO.ANSI.reset()}")
      return_skip()
    end

    # Check if test directory exists
    test_dir = Path.join(lib_path, "test")

    unless File.dir?(test_dir) do
      Mix.shell().info("  #{IO.ANSI.yellow()}⚠ No test/ directory, skipping#{IO.ANSI.reset()}")
      return_skip()
    end

    # Ensure dependencies are available
    cmd_opts = [
      cd: lib_path,
      env: [{"MIX_ENV", "test"}],
      into: if(opts[:verbose], do: IO.stream(:stdio, :line), else: "")
    ]

    # Run deps.get quietly first
    System.cmd("mix", ["deps.get"], Keyword.put(cmd_opts, :into, ""))

    case System.cmd("mix", ["test"], cmd_opts) do
      {output, 0} ->
        unless opts[:quiet] do
          Mix.shell().info("  #{IO.ANSI.green()}✓ #{lib} passed#{IO.ANSI.reset()}")

          if opts[:verbose] do
            Mix.shell().info(output)
          end
        end

        :ok

      {output, _exit_code} ->
        Mix.shell().error("  #{IO.ANSI.red()}✗ #{lib} failed#{IO.ANSI.reset()}")

        unless opts[:quiet] || opts[:verbose] do
          # Show last few lines of output on failure
          output
          |> String.split("\n")
          |> Enum.take(-20)
          |> Enum.each(&Mix.shell().info("    #{&1}"))
        end

        :failed
    end
  end

  defp return_skip, do: :skipped

  defp print_summary(results, opts) do
    passed = Enum.count(results, fn {_, s} -> s == :ok end)
    failed = Enum.count(results, fn {_, s} -> s == :failed end)
    skipped = Enum.count(results, fn {_, s} -> s == :skipped end)

    Mix.shell().info("\n#{IO.ANSI.cyan()}═══ Summary ═══#{IO.ANSI.reset()}")

    unless opts[:quiet] do
      Enum.each(results, fn {lib, status} ->
        icon =
          case status do
            :ok -> "#{IO.ANSI.green()}✓#{IO.ANSI.reset()}"
            :failed -> "#{IO.ANSI.red()}✗#{IO.ANSI.reset()}"
            :skipped -> "#{IO.ANSI.yellow()}⚠#{IO.ANSI.reset()}"
          end

        Mix.shell().info("  #{icon} #{lib}")
      end)
    end

    Mix.shell().info("")
    Mix.shell().info("  #{IO.ANSI.green()}Passed:  #{passed}#{IO.ANSI.reset()}")

    if failed > 0 do
      Mix.shell().info("  #{IO.ANSI.red()}Failed:  #{failed}#{IO.ANSI.reset()}")
    end

    if skipped > 0 do
      Mix.shell().info("  #{IO.ANSI.yellow()}Skipped: #{skipped}#{IO.ANSI.reset()}")
    end

    Mix.shell().info("")
  end
end
