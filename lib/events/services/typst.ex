defmodule Events.Services.Typst do
  @moduledoc """
  Full-featured Typst document compilation via ExCmd.

  Typst is a modern typesetting system that compiles `.typ` files to PDF, PNG, SVG, or HTML.
  This module provides streaming compilation with backpressure support.

  ## Features

  - Compile documents to PDF, PNG, SVG, or HTML
  - Stream-based compilation for memory efficiency
  - Watch mode for live recompilation
  - Query document metadata and elements
  - Font management
  - Project initialization from templates

  ## Examples

      # Compile file to PDF
      {:ok, pdf_binary} = Typst.compile("document.typ")

      # Compile specific pages to PNG
      {:ok, png} = Typst.compile("document.typ",
        format: :png,
        pages: "1-3",
        ppi: 300
      )

      # Query document metadata
      {:ok, data} = Typst.query("document.typ", "<my-label>", field: :value)

      # List available fonts
      {:ok, fonts} = Typst.fonts()

  ## Environment Variables

  - `TYPST_ROOT` - Project root directory
  - `TYPST_FONT_PATHS` - Additional font directories (colon-separated)
  - `SOURCE_DATE_EPOCH` - Document creation timestamp for reproducible builds

  """

  require Logger

  # Type definitions

  @type format :: :pdf | :png | :svg | :html
  @type pdf_standard ::
          :"1.4"
          | :"1.5"
          | :"1.6"
          | :"1.7"
          | :"2.0"
          | :"a-1b"
          | :"a-1a"
          | :"a-2b"
          | :"a-2u"
          | :"a-2a"
          | :"a-3b"
          | :"a-3u"
          | :"a-3a"
          | :"a-4"
          | :"a-4f"
          | :"a-4e"
          | :"ua-1"
  @type diagnostic_format :: :human | :short
  @type deps_format :: :json | :zero | :make

  @type compile_opts :: [
          format: format(),
          output: Path.t(),
          root: Path.t(),
          font_path: Path.t() | [Path.t()],
          input: %{String.t() => String.t()},
          pages: String.t(),
          ppi: pos_integer(),
          pdf_standard: pdf_standard() | [pdf_standard()],
          no_pdf_tags: boolean(),
          ignore_system_fonts: boolean(),
          ignore_embedded_fonts: boolean(),
          package_path: Path.t(),
          package_cache_path: Path.t(),
          creation_timestamp: integer(),
          jobs: pos_integer(),
          diagnostic_format: diagnostic_format(),
          features: [:html | :a11y_extras],
          open: boolean() | String.t(),
          timings: Path.t(),
          deps: Path.t(),
          deps_format: deps_format()
        ]

  @type query_opts :: [
          root: Path.t(),
          font_path: Path.t() | [Path.t()],
          input: %{String.t() => String.t()},
          field: atom() | String.t(),
          one: boolean(),
          target: :paged | :html,
          diagnostic_format: diagnostic_format()
        ]

  @type watch_opts :: [
          format: format(),
          root: Path.t(),
          font_path: Path.t() | [Path.t()],
          input: %{String.t() => String.t()},
          ppi: pos_integer(),
          diagnostic_format: diagnostic_format(),
          open: boolean() | String.t()
        ]

  @type font_opts :: [
          font_path: Path.t() | [Path.t()],
          ignore_system_fonts: boolean(),
          variants: boolean()
        ]

  @type init_opts :: [
          name: String.t(),
          force: boolean()
        ]

  # ============================================================================
  # Compile
  # ============================================================================

  @doc """
  Compiles a Typst file to the specified format.

  Returns the compiled binary when output is stdout (default), or `:ok` when
  writing to a file.

  ## Options

    * `:format` - Output format: `:pdf` (default), `:png`, `:svg`, or `:html`
    * `:output` - Output file path (defaults to stdout)
    * `:root` - Project root for absolute paths
    * `:font_path` - Additional font directories (string or list)
    * `:input` - Key-value pairs accessible via `sys.inputs` in the document
    * `:pages` - Pages to export (e.g., "1,3-5,8-")
    * `:ppi` - Pixels per inch for PNG (default: 144)
    * `:pdf_standard` - PDF standard(s) to enforce (e.g., `:"a-2b"`)
    * `:no_pdf_tags` - Disable tagged PDF output
    * `:ignore_system_fonts` - Don't search system fonts
    * `:ignore_embedded_fonts` - Don't use Typst's embedded fonts
    * `:package_path` - Custom local packages directory
    * `:package_cache_path` - Custom package cache directory
    * `:creation_timestamp` - UNIX timestamp for reproducible builds
    * `:jobs` - Parallel compilation jobs (default: CPU count)
    * `:diagnostic_format` - Error format: `:human` (default) or `:short`
    * `:features` - Experimental features: `[:html, :a11y_extras]`
    * `:open` - Open output with default viewer or specified program
    * `:timings` - Output compilation timings to JSON file
    * `:deps` - Output dependencies to file
    * `:deps_format` - Dependencies format: `:json`, `:zero`, or `:make`

  ## Examples

      # Basic compilation
      {:ok, pdf} = Typst.compile("report.typ")

      # High-quality PNG export
      {:ok, png} = Typst.compile("diagram.typ",
        format: :png,
        ppi: 300,
        pages: "1"
      )

      # PDF/A-2b compliant output
      {:ok, pdf} = Typst.compile("thesis.typ",
        pdf_standard: :"a-2b",
        creation_timestamp: System.os_time(:second)
      )

      # With custom inputs
      {:ok, pdf} = Typst.compile("letter.typ",
        input: %{"recipient" => "John Doe", "date" => "2025-01-15"}
      )

      # Write to file
      :ok = Typst.compile("report.typ", output: "report.pdf")

  """
  @spec compile(Path.t(), compile_opts()) :: {:ok, binary()} | :ok | {:error, term()}
  def compile(input_path, opts \\ []) do
    output = Keyword.get(opts, :output)
    args = build_compile_args(input_path, output, opts)

    run_command(["typst", "compile" | args], output)
  end

  @doc """
  Compiles a Typst file, raising on error.
  """
  @spec compile!(Path.t(), compile_opts()) :: binary() | :ok
  def compile!(input_path, opts \\ []) do
    case compile(input_path, opts) do
      {:ok, result} -> result
      :ok -> :ok
      {:error, reason} -> raise "Typst compilation failed: #{format_error(reason)}"
    end
  end

  @doc """
  Compiles Typst content from a string.

  ## Examples

      {:ok, pdf} = Typst.compile_string("= Hello\\n\\nThis is *Typst*.")

      {:ok, png} = Typst.compile_string(content, format: :png, ppi: 300)

  """
  @spec compile_string(String.t(), compile_opts()) :: {:ok, binary()} | {:error, term()}
  def compile_string(content, opts \\ []) do
    args = build_compile_args("-", nil, opts)

    try do
      result =
        ExCmd.stream!(["typst", "compile" | args], input: content)
        |> Enum.into(<<>>)

      {:ok, result}
    rescue
      e in ExCmd.Stream.AbnormalExit ->
        {:error, {:exit, e.exit_status}}
    end
  end

  @doc """
  Compiles Typst content from a string, raising on error.
  """
  @spec compile_string!(String.t(), compile_opts()) :: binary()
  def compile_string!(content, opts \\ []) do
    case compile_string(content, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Typst compilation failed: #{format_error(reason)}"
    end
  end

  @doc """
  Returns a stream for compiling a Typst file.

  Useful for piping output directly to files or other streams.

  ## Examples

      Typst.stream!("large_report.typ")
      |> Stream.into(File.stream!("report.pdf"))
      |> Stream.run()

      # Stream string content
      Typst.stream_string!("= Hello", format: :pdf)
      |> Stream.into(File.stream!("hello.pdf"))
      |> Stream.run()

  """
  @spec stream!(Path.t(), compile_opts()) :: Enumerable.t()
  def stream!(input_path, opts \\ []) do
    args = build_compile_args(input_path, nil, opts)
    ExCmd.stream!(["typst", "compile" | args])
  end

  @doc """
  Returns a non-raising stream that includes exit status.
  """
  @spec stream(Path.t(), compile_opts()) :: Enumerable.t()
  def stream(input_path, opts \\ []) do
    args = build_compile_args(input_path, nil, opts)
    ExCmd.stream(["typst", "compile" | args])
  end

  @doc """
  Returns a stream for compiling Typst content from a string.
  """
  @spec stream_string!(String.t(), compile_opts()) :: Enumerable.t()
  def stream_string!(content, opts \\ []) do
    args = build_compile_args("-", nil, opts)
    ExCmd.stream!(["typst", "compile" | args], input: content)
  end

  # ============================================================================
  # Watch
  # ============================================================================

  @doc """
  Watches a Typst file for changes and recompiles.

  Returns a `Task` that can be awaited or shut down.

  ## Options

  Same as `compile/2`, plus:

    * `:on_compile` - Callback function `(path, duration_ms) -> any` called after each compile
    * `:on_error` - Callback function `(error) -> any` called on compilation errors

  ## Examples

      # Start watching
      {:ok, task} = Typst.watch("document.typ", "output.pdf")

      # With callbacks
      {:ok, task} = Typst.watch("document.typ", "output.pdf",
        on_compile: fn path, ms -> IO.puts("Compiled in \#{ms}ms") end
      )

      # Stop watching
      Typst.stop_watch(task)

  """
  @spec watch(Path.t(), Path.t(), watch_opts()) :: {:ok, Task.t()} | {:error, term()}
  def watch(input_path, output_path, opts \\ []) do
    args = build_watch_args(input_path, output_path, opts)
    on_compile = Keyword.get(opts, :on_compile)
    on_error = Keyword.get(opts, :on_error)

    task =
      Task.async(fn ->
        ExCmd.stream(["typst", "watch" | args], stderr: :redirect_to_stdout)
        |> Stream.each(fn
          chunk when is_binary(chunk) ->
            Logger.debug("[typst watch] #{String.trim(chunk)}")

            cond do
              String.contains?(chunk, "compiled successfully") and is_function(on_compile, 2) ->
                # Extract timing if available
                case Regex.run(~r/in (\d+)ms/, chunk) do
                  [_, ms] -> on_compile.(output_path, String.to_integer(ms))
                  _ -> on_compile.(output_path, 0)
                end

              String.contains?(chunk, "error") and is_function(on_error, 1) ->
                on_error.(chunk)

              true ->
                :ok
            end

          {:exit, {:status, 0}} ->
            :ok

          {:exit, {:status, code}} ->
            Logger.warning("[typst watch] exited with code #{code}")
        end)
        |> Stream.run()
      end)

    {:ok, task}
  end

  @doc """
  Stops a watch task.
  """
  @spec stop_watch(Task.t()) :: :ok
  def stop_watch(%Task{} = task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  end

  # ============================================================================
  # Query
  # ============================================================================

  @doc """
  Queries a Typst document for elements matching a selector.

  Returns the matching elements as decoded JSON.

  ## Options

    * `:field` - Extract only a specific field from results
    * `:one` - Return only the first matching element
    * `:target` - Query target: `:paged` or `:html`
    * `:root` - Project root directory
    * `:font_path` - Additional font directories
    * `:input` - Document input variables
    * `:diagnostic_format` - Error format: `:human` or `:short`

  ## Selector Syntax

  - `"<label>"` - Elements with a specific label
  - `"heading"` - All headings
  - `"heading.where(level: 1)"` - Level 1 headings
  - `"figure"` - All figures

  ## Examples

      # Query labeled metadata
      {:ok, [%{"value" => "Chapter 1"}]} = Typst.query("doc.typ", "<chapter-title>")

      # Get just the value field
      {:ok, ["Chapter 1"]} = Typst.query("doc.typ", "<chapter-title>", field: :value)

      # Get first matching element
      {:ok, %{"level" => 1, "body" => ...}} = Typst.query("doc.typ", "heading", one: true)

      # Query all headings
      {:ok, headings} = Typst.query("doc.typ", "heading")

  """
  @spec query(Path.t(), String.t(), query_opts()) :: {:ok, term()} | {:error, term()}
  def query(input_path, selector, opts \\ []) do
    args = build_query_args(input_path, selector, opts)

    try do
      result =
        ExCmd.stream!(["typst", "query" | args])
        |> Enum.into(<<>>)
        |> String.trim()

      case JSON.decode(result) do
        {:ok, data} -> {:ok, data}
        {:error, _} -> {:ok, result}
      end
    rescue
      e in ExCmd.Stream.AbnormalExit ->
        {:error, {:exit, e.exit_status}}
    end
  end

  @doc """
  Queries a Typst document, raising on error.
  """
  @spec query!(Path.t(), String.t(), query_opts()) :: term()
  def query!(input_path, selector, opts \\ []) do
    case query(input_path, selector, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Typst query failed: #{format_error(reason)}"
    end
  end

  # ============================================================================
  # Fonts
  # ============================================================================

  @doc """
  Lists available fonts.

  ## Options

    * `:font_path` - Additional font directories
    * `:ignore_system_fonts` - Don't include system fonts
    * `:variants` - Include font variants (styles, weights)

  ## Examples

      {:ok, fonts} = Typst.fonts()
      # => ["Arial", "Helvetica", "Times New Roman", ...]

      {:ok, fonts} = Typst.fonts(variants: true)
      # => ["Arial (Regular)", "Arial (Bold)", ...]

      {:ok, fonts} = Typst.fonts(font_path: "/path/to/custom/fonts")

  """
  @spec fonts(font_opts()) :: {:ok, [String.t()]} | {:error, term()}
  def fonts(opts \\ []) do
    args = build_font_args(opts)

    try do
      result =
        ExCmd.stream!(["typst", "fonts" | args])
        |> Enum.into(<<>>)
        |> String.split("\n", trim: true)

      {:ok, result}
    rescue
      e in ExCmd.Stream.AbnormalExit ->
        {:error, {:exit, e.exit_status}}
    end
  end

  @doc """
  Lists available fonts, raising on error.
  """
  @spec fonts!(font_opts()) :: [String.t()]
  def fonts!(opts \\ []) do
    case fonts(opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Typst fonts failed: #{format_error(reason)}"
    end
  end

  # ============================================================================
  # Init
  # ============================================================================

  @doc """
  Initializes a new Typst project from a template.

  ## Options

    * `:name` - Project name (defaults to template name)
    * `:force` - Overwrite existing files

  ## Examples

      # Initialize from a template
      :ok = Typst.init("@preview/charged-ieee")

      # With custom name
      :ok = Typst.init("@preview/charged-ieee", name: "my-paper")

      # In a specific directory
      :ok = Typst.init("@preview/basic-resume", path: "/path/to/project")

  """
  @spec init(String.t(), Path.t() | nil, init_opts()) :: :ok | {:error, term()}
  def init(template, path \\ nil, opts \\ []) do
    args = build_init_args(template, path, opts)

    try do
      ExCmd.stream!(["typst", "init" | args])
      |> Stream.run()

      :ok
    rescue
      e in ExCmd.Stream.AbnormalExit ->
        {:error, {:exit, e.exit_status}}
    end
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Checks if Typst is available in PATH.
  """
  @spec available?() :: boolean()
  def available? do
    System.find_executable("typst") != nil
  end

  @doc """
  Returns the Typst version.
  """
  @spec version() :: {:ok, String.t()} | {:error, :not_found}
  def version do
    if available?() do
      result =
        ExCmd.stream!(["typst", "--version"])
        |> Enum.into(<<>>)
        |> String.trim()

      {:ok, result}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns Typst version, raising if not available.
  """
  @spec version!() :: String.t()
  def version! do
    case version() do
      {:ok, v} -> v
      {:error, :not_found} -> raise "Typst not found in PATH"
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp run_command(args, output) do
    try do
      result =
        ExCmd.stream!(args)
        |> Enum.into(<<>>)

      if output do
        :ok
      else
        {:ok, result}
      end
    rescue
      e in ExCmd.Stream.AbnormalExit ->
        {:error, {:exit, e.exit_status}}
    end
  end

  defp build_compile_args(input_path, output, opts) do
    format = Keyword.get(opts, :format, :pdf)

    # Base args: input and output (stdout if nil)
    base =
      case output do
        nil -> [input_path, "-"]
        path -> [input_path, path]
      end

    base
    |> add_arg("--format", to_string(format))
    |> add_common_args(opts)
    |> add_compile_specific_args(opts)
  end

  defp build_watch_args(input_path, output_path, opts) do
    [input_path, output_path]
    |> add_common_args(opts)
    |> maybe_add_flag("--open", Keyword.get(opts, :open))
  end

  defp build_query_args(input_path, selector, opts) do
    [input_path, selector]
    |> add_common_args(opts)
    |> maybe_add_arg("--field", Keyword.get(opts, :field))
    |> maybe_add_flag("--one", Keyword.get(opts, :one))
    |> maybe_add_arg("--target", Keyword.get(opts, :target))
  end

  defp build_font_args(opts) do
    []
    |> add_font_paths(Keyword.get(opts, :font_path))
    |> maybe_add_flag("--ignore-system-fonts", Keyword.get(opts, :ignore_system_fonts))
    |> maybe_add_flag("--variants", Keyword.get(opts, :variants))
  end

  defp build_init_args(template, path, opts) do
    base = [template]

    base =
      case path do
        nil -> base
        p -> base ++ [p]
      end

    base
    |> maybe_add_arg("--name", Keyword.get(opts, :name))
    |> maybe_add_flag("--force", Keyword.get(opts, :force))
  end

  defp add_common_args(args, opts) do
    args
    |> maybe_add_arg("--root", Keyword.get(opts, :root))
    |> add_font_paths(Keyword.get(opts, :font_path))
    |> add_inputs(Keyword.get(opts, :input))
    |> maybe_add_arg("--diagnostic-format", Keyword.get(opts, :diagnostic_format))
  end

  defp add_compile_specific_args(args, opts) do
    args
    |> maybe_add_arg("--pages", Keyword.get(opts, :pages))
    |> maybe_add_arg("--ppi", Keyword.get(opts, :ppi))
    |> add_pdf_standards(Keyword.get(opts, :pdf_standard))
    |> maybe_add_flag("--no-pdf-tags", Keyword.get(opts, :no_pdf_tags))
    |> maybe_add_flag("--ignore-system-fonts", Keyword.get(opts, :ignore_system_fonts))
    |> maybe_add_flag("--ignore-embedded-fonts", Keyword.get(opts, :ignore_embedded_fonts))
    |> maybe_add_arg("--package-path", Keyword.get(opts, :package_path))
    |> maybe_add_arg("--package-cache-path", Keyword.get(opts, :package_cache_path))
    |> maybe_add_arg("--creation-timestamp", Keyword.get(opts, :creation_timestamp))
    |> maybe_add_arg("--jobs", Keyword.get(opts, :jobs))
    |> add_features(Keyword.get(opts, :features))
    |> maybe_add_flag("--open", Keyword.get(opts, :open))
    |> maybe_add_arg("--timings", Keyword.get(opts, :timings))
    |> maybe_add_arg("--deps", Keyword.get(opts, :deps))
    |> maybe_add_arg("--deps-format", Keyword.get(opts, :deps_format))
  end

  defp add_arg(args, flag, value) do
    args ++ [flag, to_string(value)]
  end

  defp maybe_add_arg(args, _flag, nil), do: args

  defp maybe_add_arg(args, flag, value) do
    args ++ [flag, to_string(value)]
  end

  defp maybe_add_flag(args, _flag, nil), do: args
  defp maybe_add_flag(args, _flag, false), do: args
  defp maybe_add_flag(args, flag, true), do: args ++ [flag]

  defp maybe_add_flag(args, flag, value) when is_binary(value) do
    args ++ [flag, value]
  end

  defp add_font_paths(args, nil), do: args
  defp add_font_paths(args, path) when is_binary(path), do: args ++ ["--font-path", path]

  defp add_font_paths(args, paths) when is_list(paths) do
    Enum.reduce(paths, args, fn path, acc -> acc ++ ["--font-path", path] end)
  end

  defp add_inputs(args, nil), do: args

  defp add_inputs(args, inputs) when is_map(inputs) do
    Enum.reduce(inputs, args, fn {k, v}, acc ->
      acc ++ ["--input", "#{k}=#{v}"]
    end)
  end

  defp add_pdf_standards(args, nil), do: args

  defp add_pdf_standards(args, standard) when is_atom(standard) do
    args ++ ["--pdf-standard", to_string(standard)]
  end

  defp add_pdf_standards(args, standards) when is_list(standards) do
    value = standards |> Enum.map(&to_string/1) |> Enum.join(",")
    args ++ ["--pdf-standard", value]
  end

  defp add_features(args, nil), do: args

  defp add_features(args, features) when is_list(features) do
    value =
      features
      |> Enum.map(fn
        :a11y_extras -> "a11y-extras"
        f -> to_string(f)
      end)
      |> Enum.join(",")

    args ++ ["--features", value]
  end

  defp format_error({:exit, code}), do: "exit code #{code}"
  defp format_error(other), do: inspect(other)
end
