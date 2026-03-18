# OmTypst API Reference

> **Always use `OmTypst`** from `libs/om_typst` for Typst document compilation.

## Quick Start

```elixir
# Compile file to PDF binary
{:ok, pdf} = OmTypst.compile("document.typ")

# Compile string to PDF
{:ok, pdf} = OmTypst.compile_string("= Hello\n\nThis is *Typst*.")

# Write to file
:ok = OmTypst.compile("report.typ", output: "report.pdf")

# Check availability
true = OmTypst.available?()
{:ok, "typst 0.14.2"} = OmTypst.version()
```

---

## API at a Glance

| Function | Returns | Description |
|----------|---------|-------------|
| `compile/2` | `{:ok, binary} \| :ok \| {:error, _}` | Compile `.typ` file |
| `compile!/2` | `binary \| :ok` | Compile, raise on error |
| `compile_string/2` | `{:ok, binary} \| :ok \| {:error, _}` | Compile string content |
| `compile_string!/2` | `binary \| :ok` | Compile string, raise on error |
| `stream!/2` | `Enumerable.t()` | Raising stream from file |
| `stream/2` | `Enumerable.t()` | Non-raising stream (includes exit status) |
| `stream_string!/2` | `Enumerable.t()` | Raising stream from string |
| `watch/3` | `{:ok, Task.t()}` | Watch file, recompile on change |
| `stop_watch/1` | `:ok` | Stop watch task |
| `query/3` | `{:ok, term} \| {:error, _}` | Query document elements |
| `query!/3` | `term` | Query, raise on error |
| `fonts/1` | `{:ok, [String.t()]} \| {:error, _}` | List available fonts |
| `fonts!/1` | `[String.t()]` | List fonts, raise on error |
| `init/3` | `:ok \| {:error, _}` | Init project from template |
| `available?/0` | `boolean` | Check if `typst` is in PATH |
| `version/0` | `{:ok, String.t()} \| {:error, :not_found}` | Get typst version |

---

## Compilation

### Output Formats

```elixir
{:ok, pdf} = OmTypst.compile("doc.typ")                         # PDF (default)
{:ok, png} = OmTypst.compile("doc.typ", format: :png)           # PNG
{:ok, svg} = OmTypst.compile("doc.typ", format: :svg)           # SVG
{:ok, html} = OmTypst.compile("doc.typ", format: :html,         # HTML (experimental)
                features: [:html])
```

### To Memory vs File

```elixir
# Returns binary in memory
{:ok, pdf_binary} = OmTypst.compile("doc.typ")

# Writes to file, returns :ok
:ok = OmTypst.compile("doc.typ", output: "output.pdf")

# Same for compile_string
{:ok, pdf} = OmTypst.compile_string(content)
:ok = OmTypst.compile_string(content, output: "output.pdf")
```

### Page Selection

```elixir
OmTypst.compile("doc.typ", pages: "1")         # Single page
OmTypst.compile("doc.typ", pages: "1-5")       # Range
OmTypst.compile("doc.typ", pages: "1,3-5,8-")  # Multiple selections
OmTypst.compile("doc.typ", pages: "10-")        # Page 10 to end
```

### PNG Resolution

```elixir
OmTypst.compile("doc.typ", format: :png, ppi: 72)   # Low res
OmTypst.compile("doc.typ", format: :png, ppi: 144)  # Default
OmTypst.compile("doc.typ", format: :png, ppi: 300)  # High res / print
OmTypst.compile("doc.typ", format: :png, ppi: 600)  # Ultra high res
```

### Compile from String

```elixir
content = """
#set page(paper: "a4", margin: 2cm)
= My Document
This is *bold* and _italic_.
"""

{:ok, pdf} = OmTypst.compile_string(content)
{:ok, png} = OmTypst.compile_string(content, format: :png, ppi: 300)
:ok = OmTypst.compile_string(content, output: "doc.pdf")
```

---

## Document Variables (Inputs)

Pass dynamic data from Elixir into Typst via `sys.inputs`:

```elixir
# Elixir side
{:ok, pdf} = OmTypst.compile("letter.typ",
  input: %{
    "recipient" => "John Doe",
    "date" => "2025-01-15",
    "amount" => 42  # Non-string values are coerced via to_string
  }
)
```

```typst
// Typst side (letter.typ)
#let recipient = sys.inputs.at("recipient", default: "")
#let date = sys.inputs.at("date", default: datetime.today().display())
#let amount = sys.inputs.at("amount", default: "0")

Dear #recipient,

As of #date, your balance is #amount.
```

---

## Streaming

For large documents or piping directly to files/storage:

```elixir
# Stream file compilation to disk
OmTypst.stream!("large_report.typ")
|> Stream.into(File.stream!("report.pdf"))
|> Stream.run()

# Stream string content
OmTypst.stream_string!("= Hello", format: :pdf)
|> Stream.into(File.stream!("hello.pdf"))
|> Stream.run()

# Stream with format options
OmTypst.stream!("diagram.typ", format: :png, ppi: 300)
|> Stream.into(File.stream!("diagram.png"))
|> Stream.run()

# Non-raising stream (includes exit status tuples)
OmTypst.stream("doc.typ")
|> Enum.each(fn
  chunk when is_binary(chunk) -> IO.write(chunk)
  {:exit, {:status, 0}}      -> IO.puts("Done")
  {:exit, {:status, code}}   -> IO.puts("Failed: #{code}")
end)
```

---

## Watch Mode

Automatically recompile when the source file changes:

```elixir
# Basic watch
{:ok, task} = OmTypst.watch("document.typ", "output.pdf")

# With callbacks
{:ok, task} = OmTypst.watch("document.typ", "output.pdf",
  on_compile: fn path, duration_ms ->
    IO.puts("Compiled #{path} in #{duration_ms}ms")
  end,
  on_error: fn error ->
    IO.puts("Error: #{error}")
  end
)

# Stop watching (graceful shutdown)
OmTypst.stop_watch(task)
```

### Callbacks

| Callback | Signature | When |
|----------|-----------|------|
| `:on_compile` | `(path, duration_ms) -> any` | After successful compilation |
| `:on_error` | `(error_string) -> any` | On compilation error |

---

## Query API

Extract structured data from compiled documents:

### Selectors

```elixir
# By label
{:ok, results} = OmTypst.query("doc.typ", "<my-label>")

# By element type
{:ok, headings} = OmTypst.query("doc.typ", "heading")

# Filtered
{:ok, h1s} = OmTypst.query("doc.typ", "heading.where(level: 1)")

# Figures
{:ok, figs} = OmTypst.query("doc.typ", "figure")
```

### Options

```elixir
# Extract specific field from results
{:ok, values} = OmTypst.query("doc.typ", "<my-label>", field: :value)

# Expect exactly one match (errors if 0 or 2+)
{:ok, result} = OmTypst.query("doc.typ", "<unique-label>", one: true)

# With document inputs
{:ok, data} = OmTypst.query("doc.typ", "heading", input: %{"lang" => "en"})
```

### Typst Side (metadata for queries)

```typst
// Attach queryable metadata in your .typ file
#metadata("Chapter 1") <chapter-title>
#metadata((author: "Jane", year: 2025)) <doc-info>
```

```elixir
{:ok, [%{"value" => "Chapter 1"}]} = OmTypst.query("doc.typ", "<chapter-title>")
{:ok, [%{"value" => %{"author" => "Jane", "year" => 2025}}]} = OmTypst.query("doc.typ", "<doc-info>")
```

---

## Font Management

```elixir
# List all available fonts
{:ok, fonts} = OmTypst.fonts()
# => ["Arial", "Helvetica", "Times New Roman", ...]

# Include style/weight variants
{:ok, fonts} = OmTypst.fonts(variants: true)
# => ["Arial (Regular)", "Arial (Bold)", ...]

# Custom font directory
{:ok, fonts} = OmTypst.fonts(font_path: "/path/to/fonts")
{:ok, fonts} = OmTypst.fonts(font_path: ["/brand/fonts", "/project/fonts"])

# Only embedded fonts (no system)
{:ok, fonts} = OmTypst.fonts(ignore_system_fonts: true)
```

### Using Custom Fonts in Compilation

```elixir
{:ok, pdf} = OmTypst.compile("doc.typ",
  font_path: ["/project/fonts", "/brand/fonts"],
  ignore_system_fonts: true   # Only use provided fonts
)
```

---

## Project Templates

```elixir
# Init from Typst Universe template
:ok = OmTypst.init("@preview/charged-ieee")
:ok = OmTypst.init("@preview/basic-resume")

# Into specific directory
:ok = OmTypst.init("@preview/charged-ieee", "papers/my-paper")

# With custom project name
:ok = OmTypst.init("@preview/basic-resume", nil, name: "john-resume")

# Overwrite existing files
:ok = OmTypst.init("@preview/charged-ieee", "existing-dir", force: true)
```

---

## PDF Standards

```elixir
# PDF/A for archival
{:ok, pdf} = OmTypst.compile("doc.typ", pdf_standard: :"a-2b")

# Multiple standards
{:ok, pdf} = OmTypst.compile("doc.typ", pdf_standard: [:"a-2b", :"ua-1"])

# Reproducible builds (fixed timestamp)
{:ok, pdf} = OmTypst.compile("doc.typ",
  pdf_standard: :"a-2b",
  creation_timestamp: System.os_time(:second)
)

# Disable accessibility tags
{:ok, pdf} = OmTypst.compile("doc.typ", no_pdf_tags: true)
```

### Available Standards

| Standard | Description |
|----------|-------------|
| `:"1.4"` to `:"2.0"` | PDF version |
| `:"a-1b"`, `:"a-1a"` | PDF/A-1 (archival) |
| `:"a-2b"`, `:"a-2u"`, `:"a-2a"` | PDF/A-2 (archival, most common) |
| `:"a-3b"`, `:"a-3u"`, `:"a-3a"` | PDF/A-3 (archival + attachments) |
| `:"a-4"`, `:"a-4f"`, `:"a-4e"` | PDF/A-4 |
| `:"ua-1"` | PDF/UA-1 (accessibility) |

---

## Compile Options Reference

### Common Options (compile, compile_string, stream, watch)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:format` | `:pdf \| :png \| :svg \| :html` | `:pdf` | Output format |
| `:root` | `Path.t()` | - | Project root for absolute paths |
| `:font_path` | `Path.t() \| [Path.t()]` | - | Additional font directories |
| `:input` | `%{String.t() => term()}` | - | Document variables (`sys.inputs`) |
| `:diagnostic_format` | `:human \| :short` | `:human` | Error output format |

### Compile-Only Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:output` | `Path.t()` | - | Write to file instead of returning binary |
| `:pages` | `String.t()` | - | Pages to export (`"1,3-5,8-"`) |
| `:ppi` | `pos_integer()` | 144 | PNG pixels per inch |
| `:pdf_standard` | `atom \| [atom]` | - | PDF standard(s) to enforce |
| `:no_pdf_tags` | `boolean()` | - | Disable tagged PDF output |
| `:ignore_system_fonts` | `boolean()` | - | Don't search system fonts |
| `:ignore_embedded_fonts` | `boolean()` | - | Don't use Typst's bundled fonts |
| `:package_path` | `Path.t()` | - | Local packages directory |
| `:package_cache_path` | `Path.t()` | - | Package cache directory |
| `:creation_timestamp` | `non_neg_integer()` | - | UNIX timestamp for reproducible builds |
| `:jobs` | `pos_integer()` | CPU count | Parallel compilation jobs |
| `:features` | `[:html \| :a11y_extras]` | - | Experimental features |
| `:open` | `boolean() \| String.t()` | - | Open output (true = default viewer, string = app name) |
| `:timings` | `Path.t()` | - | Output compilation timings to JSON file |
| `:deps` | `Path.t()` | - | Output dependencies to file |
| `:deps_format` | `:json \| :zero \| :make` | - | Dependencies file format |

### Query Options

| Option | Type | Description |
|--------|------|-------------|
| `:field` | `atom \| String.t()` | Extract specific field from results |
| `:one` | `boolean()` | Expect exactly one match (errors if 0 or 2+) |
| `:target` | `:paged \| :html` | Query target |

### Watch Options

All common options plus:

| Option | Type | Description |
|--------|------|-------------|
| `:on_compile` | `(path, ms) -> any` | Callback after successful compile |
| `:on_error` | `(error) -> any` | Callback on compilation error |

### Font Options

| Option | Type | Description |
|--------|------|-------------|
| `:font_path` | `Path.t() \| [Path.t()]` | Additional font directories |
| `:ignore_system_fonts` | `boolean()` | Exclude system fonts |
| `:variants` | `boolean()` | Include style/weight variants |

### Init Options

| Option | Type | Description |
|--------|------|-------------|
| `:name` | `String.t()` | Project name (defaults to template name) |
| `:force` | `boolean()` | Overwrite existing files |

---

## Error Handling

All non-raising functions return `{:ok, _} | {:error, _}`:

```elixir
case OmTypst.compile("doc.typ") do
  {:ok, pdf} -> send_pdf(pdf)
  {:error, {:exit, code}} -> Logger.error("Typst exited with code #{code}")
end

case OmTypst.query("doc.typ", "heading") do
  {:ok, data} -> process(data)
  {:error, {:exit, code}} -> Logger.error("Query failed: exit #{code}")
  {:error, {:invalid_json, raw}} -> Logger.error("Bad JSON: #{raw}")
end
```

### Error Types

| Error | When |
|-------|------|
| `{:error, {:exit, code}}` | Typst process exited with non-zero code |
| `{:error, {:invalid_json, raw}}` | Query returned non-JSON output |
| `{:error, :not_found}` | `version/0` when typst not in PATH |

### Raising Variants

Every function has a `!` variant that raises `RuntimeError`:

```elixir
pdf = OmTypst.compile!("doc.typ")          # raises on error
data = OmTypst.query!("doc.typ", "heading") # raises on error
fonts = OmTypst.fonts!()                    # raises on error
version = OmTypst.version!()               # raises if not found
```

---

## Real-World Patterns

### Invoice Generation

```elixir
def generate_invoice(invoice) do
  OmTypst.compile("templates/invoice.typ",
    input: %{
      "number" => invoice.number,
      "customer" => invoice.customer.name,
      "items" => Jason.encode!(invoice.items),
      "total" => Money.to_string(invoice.total)
    },
    pdf_standard: :"a-2b"
  )
end
```

### Batch PDF Generation

```elixir
def generate_certificates(attendees) do
  attendees
  |> Task.async_stream(fn attendee ->
    {:ok, pdf} = OmTypst.compile("templates/cert.typ",
      input: %{
        "name" => attendee.name,
        "event" => attendee.event_name,
        "date" => Date.to_string(attendee.date)
      }
    )
    {attendee, pdf}
  end, max_concurrency: System.schedulers_online())
  |> Enum.map(fn {:ok, result} -> result end)
end
```

### Dynamic Report from String

```elixir
def monthly_report(data) do
  content = """
  #set document(title: "Monthly Report")
  #set page(paper: "a4", margin: 2cm)

  = Monthly Report - #{Date.utc_today()}

  #{format_table(data)}
  """

  OmTypst.compile_string(content)
end
```

### Stream Large Document to S3

```elixir
def compile_and_upload(path, s3_key, config) do
  OmTypst.stream!(path, format: :pdf)
  |> Stream.into(File.stream!("/tmp/output.pdf"))
  |> Stream.run()

  OmS3.put(s3_key, File.read!("/tmp/output.pdf"), config)
end
```

### Table of Contents Extraction

```elixir
def extract_toc(path) do
  {:ok, headings} = OmTypst.query(path, "heading")

  Enum.map(headings, fn h ->
    %{level: h["level"], text: get_in(h, ["body", "text"])}
  end)
end
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TYPST_ROOT` | Default project root directory |
| `TYPST_FONT_PATHS` | Additional font directories (colon-separated) |
| `SOURCE_DATE_EPOCH` | Unix timestamp for reproducible builds |

---

## Dependencies

- **`ex_cmd`** (~> 0.12) - Process execution with streaming
- **System**: `typst` binary must be in PATH
