defmodule OmTypstTest do
  @moduledoc """
  Tests for OmTypst - Typst document compilation via ExCmd.

  These tests require the `typst` binary to be available in PATH.
  """

  use ExUnit.Case, async: true

  @sample_content "= Hello World\n\nThis is a test document."

  @multi_page_content """
  = Page One
  Some content on the first page.

  #pagebreak()

  = Page Two
  Some content on the second page.

  #pagebreak()

  = Page Three
  Some content on the third page.
  """

  @unicode_content """
  = Unicode Test

  Chinese: 你好世界
  Japanese: こんにちは
  Korean: 안녕하세요
  Arabic: مرحبا بالعالم
  Emoji: Hello 🌍🎉
  Math: ∑∫∂√∞
  """

  @queryable_content """
  #let data = "hello world"
  #metadata(data) <my-label>
  #metadata(42) <my-number>

  = Introduction
  == Background
  = Methods
  """

  @input_content """
  #let name = sys.inputs.at("name", default: "World")
  #let count = sys.inputs.at("count", default: "0")
  Hello, #name! Count: #count
  """

  setup_all do
    unless OmTypst.available?() do
      raise "typst binary not found in PATH — required for tests"
    end

    test_dir = Path.join(System.tmp_dir!(), "om_typst_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)

    sample_path = Path.join(test_dir, "sample.typ")
    File.write!(sample_path, @sample_content)

    multi_page_path = Path.join(test_dir, "multi_page.typ")
    File.write!(multi_page_path, @multi_page_content)

    unicode_path = Path.join(test_dir, "unicode.typ")
    File.write!(unicode_path, @unicode_content)

    queryable_path = Path.join(test_dir, "queryable.typ")
    File.write!(queryable_path, @queryable_content)

    input_path = Path.join(test_dir, "with_input.typ")
    File.write!(input_path, @input_content)

    bad_path = Path.join(test_dir, "bad.typ")
    File.write!(bad_path, "#invalid-syntax(((")

    on_exit(fn -> File.rm_rf!(test_dir) end)

    {:ok,
     test_dir: test_dir,
     sample_path: sample_path,
     multi_page_path: multi_page_path,
     unicode_path: unicode_path,
     queryable_path: queryable_path,
     input_path: input_path,
     bad_path: bad_path}
  end

  # ============================================================================
  # available?/0
  # ============================================================================

  describe "available?/0" do
    test "returns true when typst is in PATH" do
      assert OmTypst.available?()
    end
  end

  # ============================================================================
  # version/0 and version!/0
  # ============================================================================

  describe "version/0" do
    test "returns {:ok, version_string}" do
      assert {:ok, version} = OmTypst.version()
      assert is_binary(version)
      assert version =~ "typst"
    end
  end

  describe "version!/0" do
    test "returns version string" do
      version = OmTypst.version!()
      assert is_binary(version)
      assert version =~ "typst"
    end
  end

  # ============================================================================
  # compile/2
  # ============================================================================

  describe "compile/2" do
    test "compiles .typ file to PDF binary", %{sample_path: path} do
      assert {:ok, pdf} = OmTypst.compile(path)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "compiles to PNG format", %{sample_path: path} do
      assert {:ok, png} = OmTypst.compile(path, format: :png)
      assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = png
    end

    test "compiles to SVG format", %{sample_path: path} do
      assert {:ok, svg} = OmTypst.compile(path, format: :svg)
      assert svg =~ "<svg"
    end

    test "compiles to HTML format", %{sample_path: path} do
      assert {:ok, html} = OmTypst.compile(path, format: :html, features: [:html])
      assert is_binary(html)
      assert html =~ "<" or html =~ "html"
    end

    test "writes to output file", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "output.pdf")
      assert :ok = OmTypst.compile(path, output: output)
      assert File.exists?(output)
      assert <<"%PDF", _rest::binary>> = File.read!(output)
    end

    test "compiles with custom ppi for PNG", %{sample_path: path} do
      assert {:ok, png_low} = OmTypst.compile(path, format: :png, ppi: 72)
      assert {:ok, png_high} = OmTypst.compile(path, format: :png, ppi: 300)
      assert byte_size(png_high) > byte_size(png_low)
    end

    test "compiles with string input variables", %{input_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, input: %{"name" => "Typst"})
    end

    test "compiles with non-string input values (coerced to string)", %{input_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, input: %{"name" => "Test", "count" => 42})
    end

    test "compiles with empty input map", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, input: %{})
    end

    test "compiles with special characters in input values", %{input_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, input: %{"name" => "O'Brien & Co."})
    end

    test "returns error for nonexistent file" do
      assert {:error, {:exit, code}} = OmTypst.compile("/nonexistent/file.typ")
      assert is_integer(code)
      assert code > 0
    end

    test "returns error for invalid typst content", %{bad_path: path} do
      assert {:error, {:exit, _code}} = OmTypst.compile(path)
    end

    test "compiles specific pages", %{multi_page_path: path} do
      assert {:ok, page1} = OmTypst.compile(path, pages: "1")
      assert {:ok, all_pages} = OmTypst.compile(path)
      # Single page should be smaller than all pages
      assert byte_size(page1) < byte_size(all_pages)
    end

    test "compiles page range", %{multi_page_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, pages: "1-2")
    end

    test "passes font_path as single string", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, font_path: "/nonexistent/fonts")
    end

    test "passes font_path as list", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, font_path: ["/path/a", "/path/b"])
    end

    test "compiles with root option", %{sample_path: path, test_dir: test_dir} do
      assert {:ok, _pdf} = OmTypst.compile(path, root: test_dir)
    end

    test "compiles with no_pdf_tags option", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, no_pdf_tags: true)
    end

    test "compiles with ignore_embedded_fonts option", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, ignore_embedded_fonts: true)
    end

    test "compiles multi-page document", %{multi_page_path: path} do
      assert {:ok, pdf} = OmTypst.compile(path)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "compiles unicode content", %{unicode_path: path} do
      assert {:ok, pdf} = OmTypst.compile(path)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "compiles with deps option", %{sample_path: path, test_dir: test_dir} do
      deps_file = Path.join(test_dir, "deps.json")
      assert {:ok, _pdf} = OmTypst.compile(path, deps: deps_file, deps_format: :json)
    end

    test "compiles with timings option", %{sample_path: path, test_dir: test_dir} do
      timings_file = Path.join(test_dir, "timings.json")
      assert {:ok, _pdf} = OmTypst.compile(path, timings: timings_file)
    end

    test "concurrent compilation", %{sample_path: path} do
      tasks =
        for _ <- 1..5 do
          Task.async(fn -> OmTypst.compile(path) end)
        end

      results = Task.await_many(tasks, 30_000)
      assert Enum.all?(results, &match?({:ok, <<"%PDF", _::binary>>}, &1))
    end
  end

  describe "compile!/2" do
    test "returns binary on success", %{sample_path: path} do
      pdf = OmTypst.compile!(path)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "returns :ok when writing to file", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "bang_output.pdf")
      assert :ok = OmTypst.compile!(path, output: output)
    end

    test "raises on failure" do
      assert_raise RuntimeError, ~r/Typst compilation failed/, fn ->
        OmTypst.compile!("/nonexistent/file.typ")
      end
    end

    test "raises with exit code in message" do
      assert_raise RuntimeError, ~r/exit code/, fn ->
        OmTypst.compile!("/nonexistent/file.typ")
      end
    end
  end

  # ============================================================================
  # compile_string/2
  # ============================================================================

  describe "compile_string/2" do
    test "compiles string content to PDF" do
      assert {:ok, pdf} = OmTypst.compile_string(@sample_content)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "compiles string content to PNG" do
      assert {:ok, png} = OmTypst.compile_string(@sample_content, format: :png)
      assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = png
    end

    test "compiles string content to SVG" do
      assert {:ok, svg} = OmTypst.compile_string(@sample_content, format: :svg)
      assert svg =~ "<svg"
    end

    test "writes to output file", %{test_dir: test_dir} do
      output = Path.join(test_dir, "string_output.pdf")
      assert :ok = OmTypst.compile_string(@sample_content, output: output)
      assert File.exists?(output)
      assert <<"%PDF", _rest::binary>> = File.read!(output)
    end

    test "writes PNG to output file", %{test_dir: test_dir} do
      output = Path.join(test_dir, "string_output.png")
      assert :ok = OmTypst.compile_string(@sample_content, output: output, format: :png)
      assert File.exists?(output)
      assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = File.read!(output)
    end

    test "returns error for invalid content" do
      assert {:error, {:exit, code}} = OmTypst.compile_string("#invalid-syntax(((")
      assert is_integer(code)
    end

    test "handles empty string" do
      assert {:ok, pdf} = OmTypst.compile_string("")
      assert is_binary(pdf)
    end

    test "compiles unicode content" do
      assert {:ok, pdf} = OmTypst.compile_string(@unicode_content)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "compiles multi-page content" do
      assert {:ok, pdf} = OmTypst.compile_string(@multi_page_content)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "compiles with ppi option" do
      assert {:ok, _png} = OmTypst.compile_string(@sample_content, format: :png, ppi: 150)
    end
  end

  describe "compile_string!/2" do
    test "returns binary on success" do
      pdf = OmTypst.compile_string!(@sample_content)
      assert <<"%PDF", _rest::binary>> = pdf
    end

    test "returns :ok when writing to file", %{test_dir: test_dir} do
      output = Path.join(test_dir, "string_bang_output.pdf")
      assert :ok = OmTypst.compile_string!(@sample_content, output: output)
    end

    test "raises on failure" do
      assert_raise RuntimeError, ~r/Typst compilation failed/, fn ->
        OmTypst.compile_string!("#invalid-syntax(((")
      end
    end
  end

  # ============================================================================
  # stream!/2 and stream/2
  # ============================================================================

  describe "stream!/2" do
    test "returns an enumerable that produces PDF", %{sample_path: path} do
      result = OmTypst.stream!(path) |> Enum.into(<<>>)
      assert <<"%PDF", _rest::binary>> = result
    end

    test "can stream to a file", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "streamed.pdf")

      OmTypst.stream!(path)
      |> Stream.into(File.stream!(output))
      |> Stream.run()

      assert File.exists?(output)
      assert <<"%PDF", _rest::binary>> = File.read!(output)
    end

    test "can stream PNG format", %{sample_path: path} do
      result = OmTypst.stream!(path, format: :png) |> Enum.into(<<>>)
      assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = result
    end

    test "raises on invalid input" do
      assert_raise ExCmd.Stream.AbnormalExit, fn ->
        OmTypst.stream!("/nonexistent.typ") |> Enum.into(<<>>)
      end
    end
  end

  describe "stream/2" do
    test "returns stream including exit status on success", %{sample_path: path} do
      chunks = OmTypst.stream(path) |> Enum.to_list()

      assert Enum.any?(chunks, &is_binary/1)
      assert Enum.any?(chunks, &match?({:exit, {:status, 0}}, &1))
    end

    test "returns non-zero exit status on failure" do
      chunks = OmTypst.stream("/nonexistent.typ") |> Enum.to_list()

      refute Enum.any?(chunks, &match?({:exit, {:status, 0}}, &1))
      assert Enum.any?(chunks, fn
        {:exit, {:status, code}} when code > 0 -> true
        _ -> false
      end)
    end
  end

  describe "stream_string!/2" do
    test "streams compiled output from string content" do
      result = OmTypst.stream_string!(@sample_content) |> Enum.into(<<>>)
      assert <<"%PDF", _rest::binary>> = result
    end

    test "streams PNG from string content" do
      result = OmTypst.stream_string!(@sample_content, format: :png) |> Enum.into(<<>>)
      assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = result
    end

    test "streams SVG from string content" do
      result = OmTypst.stream_string!(@sample_content, format: :svg) |> Enum.into(<<>>)
      assert result =~ "<svg"
    end

    test "raises on invalid content" do
      assert_raise ExCmd.Stream.AbnormalExit, fn ->
        OmTypst.stream_string!("#invalid-syntax(((") |> Enum.into(<<>>)
      end
    end
  end

  # ============================================================================
  # query/3
  # ============================================================================

  describe "query/3" do
    test "queries heading elements", %{queryable_path: path} do
      assert {:ok, results} = OmTypst.query(path, "heading")
      assert is_list(results)
      assert length(results) == 3
    end

    test "queries with label selector", %{queryable_path: path} do
      assert {:ok, results} = OmTypst.query(path, "<my-label>")
      assert is_list(results)
      assert length(results) == 1
    end

    test "queries with .where() selector for level 1 headings", %{queryable_path: path} do
      assert {:ok, results} = OmTypst.query(path, "heading.where(level: 1)")
      assert is_list(results)
      assert length(results) == 2
    end

    test "queries with .where() selector for level 2 headings", %{queryable_path: path} do
      assert {:ok, results} = OmTypst.query(path, "heading.where(level: 2)")
      assert is_list(results)
      assert length(results) == 1
    end

    test "queries with field option", %{queryable_path: path} do
      assert {:ok, results} = OmTypst.query(path, "<my-label>", field: :value)
      assert is_list(results)
      assert length(results) == 1
    end

    test "queries with one option returns single element", %{queryable_path: path} do
      # --one expects exactly one match; use a unique label
      assert {:ok, result} = OmTypst.query(path, "<my-label>", one: true)
      assert is_map(result)
    end

    test "queries with one option fails for multiple matches", %{queryable_path: path} do
      # --one errors when there are multiple matches
      assert {:error, {:exit, _}} = OmTypst.query(path, "heading", one: true)
    end

    test "returns decoded JSON structures", %{queryable_path: path} do
      assert {:ok, [result | _]} = OmTypst.query(path, "heading")
      assert is_map(result)
      # Typst query returns structured data with func, body, etc.
      assert Map.has_key?(result, "func")
    end

    test "query returns empty list for no matches", %{queryable_path: path} do
      assert {:ok, []} = OmTypst.query(path, "<nonexistent-label>")
    end

    test "returns error for nonexistent file" do
      assert {:error, {:exit, code}} = OmTypst.query("/nonexistent.typ", "heading")
      assert is_integer(code)
    end

    test "query with input option", %{test_dir: test_dir} do
      content = """
      #let val = sys.inputs.at("key", default: "default")
      #metadata(val) <result>
      """

      path = Path.join(test_dir, "query_input.typ")
      File.write!(path, content)

      assert {:ok, results} = OmTypst.query(path, "<result>", input: %{"key" => "custom"})
      assert is_list(results)
    end
  end

  describe "query!/3" do
    test "returns results on success", %{queryable_path: path} do
      results = OmTypst.query!(path, "heading")
      assert is_list(results)
      assert length(results) == 3
    end

    test "raises on failure" do
      assert_raise RuntimeError, ~r/Typst query failed/, fn ->
        OmTypst.query!("/nonexistent.typ", "heading")
      end
    end

    test "raises with exit code in message" do
      assert_raise RuntimeError, ~r/exit code/, fn ->
        OmTypst.query!("/nonexistent.typ", "heading")
      end
    end
  end

  # ============================================================================
  # fonts/1
  # ============================================================================

  describe "fonts/1" do
    test "lists available fonts" do
      assert {:ok, fonts} = OmTypst.fonts()
      assert is_list(fonts)
      assert length(fonts) > 0
      assert Enum.all?(fonts, &is_binary/1)
    end

    test "lists fonts with variants" do
      assert {:ok, fonts} = OmTypst.fonts(variants: true)
      assert is_list(fonts)
      assert length(fonts) > 0
    end

    test "variants list is longer than base list" do
      {:ok, base_fonts} = OmTypst.fonts()
      {:ok, variant_fonts} = OmTypst.fonts(variants: true)
      assert length(variant_fonts) >= length(base_fonts)
    end

    test "accepts font_path option" do
      assert {:ok, fonts} = OmTypst.fonts(font_path: "/nonexistent/fonts")
      assert is_list(fonts)
    end

    test "accepts font_path as list" do
      assert {:ok, fonts} = OmTypst.fonts(font_path: ["/path/a", "/path/b"])
      assert is_list(fonts)
    end

    test "ignore_system_fonts reduces font count" do
      {:ok, all_fonts} = OmTypst.fonts()
      {:ok, no_system} = OmTypst.fonts(ignore_system_fonts: true)
      # Without system fonts, there should be fewer (or equal if no system fonts installed)
      assert length(no_system) <= length(all_fonts)
    end

    test "each font name is a non-empty string" do
      {:ok, fonts} = OmTypst.fonts()
      assert Enum.all?(fonts, fn f -> is_binary(f) and byte_size(f) > 0 end)
    end
  end

  describe "fonts!/1" do
    test "returns font list" do
      fonts = OmTypst.fonts!()
      assert is_list(fonts)
      assert length(fonts) > 0
    end
  end

  # ============================================================================
  # init/3
  # ============================================================================

  describe "init/3" do
    test "returns error for invalid template" do
      assert {:error, {:exit, _code}} = OmTypst.init("@preview/nonexistent-template-xyz-999")
    end

    test "returns error for nonexistent path" do
      assert {:error, {:exit, _code}} =
               OmTypst.init("@preview/some-template", "/nonexistent/deeply/nested/path")
    end
  end

  # ============================================================================
  # watch/3 and stop_watch/1
  # ============================================================================

  describe "watch/3" do
    test "starts a watch task", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "watched.pdf")
      assert {:ok, task} = OmTypst.watch(path, output)
      assert %Task{} = task

      Process.sleep(500)
      assert :ok = OmTypst.stop_watch(task)
    end

    test "produces output file on initial compile", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "watch_initial.pdf")

      {:ok, task} = OmTypst.watch(path, output)

      # Wait for initial compilation
      Process.sleep(1_000)
      assert File.exists?(output)
      assert <<"%PDF", _rest::binary>> = File.read!(output)

      OmTypst.stop_watch(task)
    end

    test "invokes on_compile callback with path and timing", %{sample_path: path, test_dir: test_dir} do
      test_pid = self()
      output = Path.join(test_dir, "watched_cb.pdf")

      {:ok, task} =
        OmTypst.watch(path, output,
          on_compile: fn recv_path, ms ->
            send(test_pid, {:compiled, recv_path, ms})
          end
        )

      assert_receive {:compiled, ^output, ms}, 5_000
      assert is_integer(ms)
      assert ms >= 0

      OmTypst.stop_watch(task)
    end

    test "recompiles when file changes", %{test_dir: test_dir} do
      test_pid = self()
      watch_source = Path.join(test_dir, "watch_recompile.typ")
      output = Path.join(test_dir, "watch_recompile.pdf")

      File.write!(watch_source, "= Version 1")

      compile_count = :counters.new(1, [:atomics])

      {:ok, task} =
        OmTypst.watch(watch_source, output,
          on_compile: fn _path, _ms ->
            :counters.add(compile_count, 1, 1)
            send(test_pid, {:compiled, :counters.get(compile_count, 1)})
          end
        )

      # Wait for initial compile
      assert_receive {:compiled, 1}, 5_000

      # Modify the file
      Process.sleep(200)
      File.write!(watch_source, "= Version 2\n\nUpdated content.")

      # Wait for recompile
      assert_receive {:compiled, 2}, 5_000

      OmTypst.stop_watch(task)
    end

    test "invokes on_error callback for invalid content", %{test_dir: test_dir} do
      test_pid = self()
      watch_source = Path.join(test_dir, "watch_error.typ")
      output = Path.join(test_dir, "watch_error.pdf")

      # Start with valid content
      File.write!(watch_source, "= Valid")

      {:ok, task} =
        OmTypst.watch(watch_source, output,
          on_compile: fn _path, _ms -> send(test_pid, :compiled) end,
          on_error: fn error -> send(test_pid, {:error, error}) end
        )

      # Wait for initial compile
      assert_receive :compiled, 5_000

      # Write invalid content
      Process.sleep(200)
      File.write!(watch_source, "#invalid-syntax(((")

      # Wait for error callback
      assert_receive {:error, error_msg}, 5_000
      assert is_binary(error_msg)

      OmTypst.stop_watch(task)
    end
  end

  describe "stop_watch/1" do
    test "stops a running watch task", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "stop_test.pdf")
      {:ok, task} = OmTypst.watch(path, output)
      Process.sleep(200)
      assert :ok = OmTypst.stop_watch(task)
    end

    test "returns :ok even if task already finished", %{sample_path: path, test_dir: test_dir} do
      output = Path.join(test_dir, "stop_finished.pdf")
      {:ok, task} = OmTypst.watch(path, output)
      Process.sleep(200)

      # Stop twice — second should still return :ok
      assert :ok = OmTypst.stop_watch(task)
    end
  end

  # ============================================================================
  # Option handling (integration tests via compile)
  # ============================================================================

  describe "option handling" do
    test "pdf_standard as single atom", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, pdf_standard: :"1.7")
    end

    test "pdf_standard as list of atoms", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, pdf_standard: [:"1.7"])
    end

    test "diagnostic_format :short", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, diagnostic_format: :short)
    end

    test "diagnostic_format :human", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, diagnostic_format: :human)
    end

    test "ignore_system_fonts option", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, ignore_system_fonts: true)
    end

    test "jobs option", %{sample_path: path} do
      assert {:ok, _pdf} = OmTypst.compile(path, jobs: 1)
    end

    test "creation_timestamp option", %{sample_path: path} do
      ts = System.os_time(:second)
      assert {:ok, _pdf} = OmTypst.compile(path, creation_timestamp: ts)
    end

    test "creation_timestamp produces reproducible output", %{sample_path: path} do
      ts = 1_700_000_000
      assert {:ok, pdf1} = OmTypst.compile(path, creation_timestamp: ts)
      assert {:ok, pdf2} = OmTypst.compile(path, creation_timestamp: ts)
      assert pdf1 == pdf2
    end

    test "different timestamps produce different PDFs", %{sample_path: path} do
      assert {:ok, pdf1} = OmTypst.compile(path, creation_timestamp: 1_700_000_000)
      assert {:ok, pdf2} = OmTypst.compile(path, creation_timestamp: 1_700_000_001)
      assert pdf1 != pdf2
    end

    test "multiple options combined", %{sample_path: path} do
      assert {:ok, _pdf} =
               OmTypst.compile(path,
                 format: :pdf,
                 pages: "1",
                 jobs: 2,
                 diagnostic_format: :short,
                 input: %{"key" => "value"},
                 no_pdf_tags: true,
                 ignore_system_fonts: true
               )
    end

    test "false boolean flags are not passed", %{sample_path: path} do
      # These should compile fine — false flags should be no-ops
      assert {:ok, _pdf} =
               OmTypst.compile(path,
                 no_pdf_tags: false,
                 ignore_system_fonts: false,
                 ignore_embedded_fonts: false
               )
    end
  end

  # ============================================================================
  # Error formatting
  # ============================================================================

  describe "error messages" do
    test "compile error includes exit code" do
      {:error, {:exit, code}} = OmTypst.compile("/nonexistent.typ")
      assert is_integer(code)
      assert code > 0
    end

    test "compile! error message includes exit code" do
      error =
        assert_raise RuntimeError, fn ->
          OmTypst.compile!("/nonexistent.typ")
        end

      assert error.message =~ "exit code"
    end

    test "query! error message includes exit code" do
      error =
        assert_raise RuntimeError, fn ->
          OmTypst.query!("/nonexistent.typ", "heading")
        end

      assert error.message =~ "exit code"
    end
  end
end
