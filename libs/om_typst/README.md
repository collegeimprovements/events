# OmTypst

Typst document compilation for Elixir.

## Installation

```elixir
def deps do
  [
    {:om_typst, "~> 0.1.0"},
    {:ex_cmd, "~> 0.10"}
  ]
end
```

**System Requirement**: Typst must be installed:

```bash
# macOS
brew install typst

# Cargo (any platform)
cargo install --git https://github.com/typst/typst --locked typst-cli

# Download binary
# https://github.com/typst/typst/releases
```

## Quick Start

```elixir
# Compile to PDF
{:ok, pdf_binary} = OmTypst.compile("document.typ")

# Compile to PNG
{:ok, png_binary} = OmTypst.compile("diagram.typ", format: :png, ppi: 300)

# Write to file
:ok = OmTypst.compile("report.typ", output: "report.pdf")

# Compile from string
{:ok, pdf} = OmTypst.compile_string("= Hello\\n\\nThis is *Typst*.")
```

## Features

- **Multiple Formats** - PDF, PNG, SVG, HTML output
- **Stream-Based** - Memory-efficient compilation
- **Watch Mode** - Live recompilation on changes
- **Query API** - Extract document metadata and elements
- **Font Management** - List and manage fonts
- **Templates** - Initialize projects from templates
- **PDF Standards** - PDF/A compliance support

---

## Compilation

### Basic Compilation

```elixir
# To PDF (default)
{:ok, pdf} = OmTypst.compile("document.typ")

# To PNG
{:ok, png} = OmTypst.compile("diagram.typ", format: :png)

# To SVG
{:ok, svg} = OmTypst.compile("logo.typ", format: :svg)

# To HTML (experimental)
{:ok, html} = OmTypst.compile("page.typ", format: :html)
```

### Write to File

```elixir
# Returns :ok when writing to file
:ok = OmTypst.compile("report.typ", output: "report.pdf")
:ok = OmTypst.compile("chart.typ", output: "chart.png", format: :png)
```

### Compile from String

```elixir
content = """
= My Document

This is *bold* and _italic_ text.

#lorem(50)
"""

{:ok, pdf} = OmTypst.compile_string(content)
{:ok, png} = OmTypst.compile_string(content, format: :png, ppi: 144)
```

### Page Selection

```elixir
# Single page
{:ok, png} = OmTypst.compile("document.typ", format: :png, pages: "1")

# Page range
{:ok, pdf} = OmTypst.compile("document.typ", pages: "1-5")

# Multiple selections
{:ok, pdf} = OmTypst.compile("document.typ", pages: "1,3-5,8-")

# From page to end
{:ok, pdf} = OmTypst.compile("document.typ", pages: "10-")
```

### PNG Quality

```elixir
# Default: 144 PPI
{:ok, png} = OmTypst.compile("diagram.typ", format: :png)

# High resolution: 300 PPI
{:ok, png} = OmTypst.compile("diagram.typ", format: :png, ppi: 300)

# Print quality: 600 PPI
{:ok, png} = OmTypst.compile("diagram.typ", format: :png, ppi: 600)
```

---

## Document Variables

Pass variables to your Typst document:

```elixir
# In Elixir
{:ok, pdf} = OmTypst.compile("letter.typ",
  input: %{
    "recipient" => "John Doe",
    "date" => "January 15, 2025",
    "subject" => "Contract Review"
  }
)
```

```typst
// In letter.typ
#let recipient = sys.inputs.at("recipient", default: "")
#let date = sys.inputs.at("date", default: datetime.today().display())

Dear #recipient,

Date: #date

...
```

---

## PDF Standards

Generate compliant PDFs:

```elixir
# PDF/A-2b (archival)
{:ok, pdf} = OmTypst.compile("thesis.typ", pdf_standard: :"a-2b")

# Multiple standards
{:ok, pdf} = OmTypst.compile("document.typ", pdf_standard: [:"a-2b", :"ua-1"])

# With reproducible timestamp
{:ok, pdf} = OmTypst.compile("document.typ",
  pdf_standard: :"a-2b",
  creation_timestamp: System.os_time(:second)
)

# Disable PDF tags (accessibility metadata)
{:ok, pdf} = OmTypst.compile("simple.typ", no_pdf_tags: true)
```

### Available Standards

| Standard | Description |
|----------|-------------|
| `:"1.4"` - `:"2.0"` | PDF version |
| `:"a-1b"`, `:"a-1a"` | PDF/A-1 |
| `:"a-2b"`, `:"a-2u"`, `:"a-2a"` | PDF/A-2 |
| `:"a-3b"`, `:"a-3u"`, `:"a-3a"` | PDF/A-3 |
| `:"a-4"`, `:"a-4f"`, `:"a-4e"` | PDF/A-4 |
| `:"ua-1"` | PDF/UA-1 (accessibility) |

---

## Streaming

For large documents or piping to files:

```elixir
# Stream to file
OmTypst.stream!("large_report.typ")
|> Stream.into(File.stream!("report.pdf"))
|> Stream.run()

# Stream from string
OmTypst.stream_string!("= Hello", format: :pdf)
|> Stream.into(File.stream!("hello.pdf"))
|> Stream.run()

# Non-raising stream (includes exit status)
OmTypst.stream("document.typ")
|> Enum.to_list()
```

---

## Watch Mode

Automatically recompile on file changes:

```elixir
# Start watching
{:ok, task} = OmTypst.watch("document.typ", "output.pdf")

# With callbacks
{:ok, task} = OmTypst.watch("document.typ", "output.pdf",
  on_compile: fn path, duration_ms ->
    IO.puts("Compiled #{path} in #{duration_ms}ms")
  end,
  on_error: fn error ->
    IO.puts("Compilation error: #{error}")
  end
)

# Stop watching
OmTypst.stop_watch(task)
```

### Watch with Auto-Open

```elixir
# Open in default PDF viewer
{:ok, task} = OmTypst.watch("document.typ", "output.pdf", open: true)

# Open with specific application
{:ok, task} = OmTypst.watch("document.typ", "output.pdf", open: "Preview")
```

---

## Query API

Extract information from documents:

### Query by Label

```typst
// In document.typ
#metadata("Chapter 1") <chapter-title>
#metadata((author: "John", year: 2025)) <doc-info>
```

```elixir
# Get labeled metadata
{:ok, [%{"value" => "Chapter 1"}]} = OmTypst.query("document.typ", "<chapter-title>")

# Get specific field
{:ok, ["Chapter 1"]} = OmTypst.query("document.typ", "<chapter-title>", field: :value)

# Complex metadata
{:ok, [%{"value" => %{"author" => "John", "year" => 2025}}]} =
  OmTypst.query("document.typ", "<doc-info>")
```

### Query Elements

```elixir
# All headings
{:ok, headings} = OmTypst.query("document.typ", "heading")

# Level 1 headings only
{:ok, h1s} = OmTypst.query("document.typ", "heading.where(level: 1)")

# First match only
{:ok, first_heading} = OmTypst.query("document.typ", "heading", one: true)

# All figures
{:ok, figures} = OmTypst.query("document.typ", "figure")
```

---

## Font Management

### List Fonts

```elixir
# All available fonts
{:ok, fonts} = OmTypst.fonts()
#=> ["Arial", "Helvetica", "Times New Roman", ...]

# With variants (styles, weights)
{:ok, fonts} = OmTypst.fonts(variants: true)
#=> ["Arial (Regular)", "Arial (Bold)", "Arial (Italic)", ...]

# Custom font directory
{:ok, fonts} = OmTypst.fonts(font_path: "/path/to/fonts")

# Exclude system fonts
{:ok, fonts} = OmTypst.fonts(ignore_system_fonts: true)
```

### Use Custom Fonts

```elixir
{:ok, pdf} = OmTypst.compile("document.typ",
  font_path: [
    "/path/to/project/fonts",
    "/path/to/brand/fonts"
  ]
)
```

---

## Project Templates

Initialize projects from Typst templates:

```elixir
# From Typst Universe
:ok = OmTypst.init("@preview/charged-ieee")
:ok = OmTypst.init("@preview/basic-resume")

# With custom project name
:ok = OmTypst.init("@preview/charged-ieee", "papers/my-paper")

# Named project
:ok = OmTypst.init("@preview/basic-resume", nil, name: "john-resume")

# Overwrite existing
:ok = OmTypst.init("@preview/charged-ieee", "existing-dir", force: true)
```

---

## Advanced Options

### Project Root

```elixir
# Set project root for absolute paths
{:ok, pdf} = OmTypst.compile("src/main.typ",
  root: "/path/to/project"
)
```

### Package Management

```elixir
{:ok, pdf} = OmTypst.compile("document.typ",
  package_path: "/path/to/local/packages",
  package_cache_path: "/path/to/cache"
)
```

### Parallel Compilation

```elixir
# Use all CPU cores (default)
{:ok, pdf} = OmTypst.compile("large.typ")

# Limit parallelism
{:ok, pdf} = OmTypst.compile("large.typ", jobs: 4)
```

### Compilation Timings

```elixir
# Output timing information
{:ok, pdf} = OmTypst.compile("document.typ",
  timings: "timings.json"
)

# Also output dependencies
{:ok, pdf} = OmTypst.compile("document.typ",
  deps: "deps.json",
  deps_format: :json  # :json, :zero, or :make
)
```

### Experimental Features

```elixir
{:ok, pdf} = OmTypst.compile("document.typ",
  features: [:html, :a11y_extras]
)
```

---

## Utility Functions

```elixir
# Check if Typst is available
OmTypst.available?()
#=> true

# Get version
{:ok, version} = OmTypst.version()
#=> {:ok, "typst 0.12.0"}

# Raising version
OmTypst.version!()
#=> "typst 0.12.0"
```

---

## Real-World Examples

### Invoice Generator

```elixir
defmodule MyApp.InvoiceGenerator do
  def generate(invoice) do
    OmTypst.compile("templates/invoice.typ",
      input: %{
        "invoice_number" => invoice.number,
        "customer_name" => invoice.customer.name,
        "items" => Jason.encode!(invoice.items),
        "total" => Money.to_string(invoice.total),
        "due_date" => Date.to_string(invoice.due_date)
      },
      pdf_standard: :"a-2b"
    )
  end
end
```

### Report Builder

```elixir
defmodule MyApp.Reports do
  def generate_monthly_report(data) do
    content = build_typst_content(data)

    case OmTypst.compile_string(content, format: :pdf) do
      {:ok, pdf} ->
        filename = "report_#{Date.utc_today()}.pdf"
        {:ok, pdf, filename}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_typst_content(data) do
    """
    #set document(title: "Monthly Report")
    #set page(paper: "a4", margin: 2cm)

    = Monthly Report

    Generated: #{DateTime.utc_now()}

    == Summary

    #{format_summary(data)}

    == Details

    #{format_details(data)}
    """
  end
end
```

### Batch PDF Generation

```elixir
defmodule MyApp.CertificateGenerator do
  def generate_certificates(attendees) do
    attendees
    |> Task.async_stream(fn attendee ->
      {:ok, pdf} = OmTypst.compile("templates/certificate.typ",
        input: %{
          "name" => attendee.name,
          "event" => attendee.event_name,
          "date" => Date.to_string(attendee.event_date)
        }
      )
      {attendee.email, pdf}
    end, max_concurrency: System.schedulers_online())
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TYPST_ROOT` | Default project root |
| `TYPST_FONT_PATHS` | Additional font directories (colon-separated) |
| `SOURCE_DATE_EPOCH` | Unix timestamp for reproducible builds |

## Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `format` | atom | `:pdf` | Output format (`:pdf`, `:png`, `:svg`, `:html`) |
| `output` | path | - | Output file (nil = return binary) |
| `pages` | string | - | Pages to export ("1,3-5,8-") |
| `ppi` | integer | 144 | PNG resolution |
| `pdf_standard` | atom/list | - | PDF standard(s) |
| `root` | path | - | Project root directory |
| `font_path` | path/list | - | Additional font directories |
| `input` | map | - | Document variables |
| `jobs` | integer | CPU count | Parallel compilation jobs |

## License

MIT
