# OmTypst Cheatsheet

> Typst document compilation for Elixir. Requires `typst` binary. For full docs, see `README.md`.

## Compilation

```elixir
# File to binary
{:ok, pdf} = OmTypst.compile("document.typ")
{:ok, png} = OmTypst.compile("diagram.typ", format: :png, ppi: 300)
{:ok, svg} = OmTypst.compile("logo.typ", format: :svg)
{:ok, html} = OmTypst.compile("page.typ", format: :html)

# File to file
:ok = OmTypst.compile("report.typ", output: "report.pdf")

# String to binary
{:ok, pdf} = OmTypst.compile_string("= Hello\n\nThis is *Typst*.")
{:ok, png} = OmTypst.compile_string(content, format: :png, ppi: 144)

# Page selection
{:ok, pdf} = OmTypst.compile("doc.typ", pages: "1-5")
{:ok, png} = OmTypst.compile("slides.typ", format: :png, pages: "1")
```

---

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `format` | `:pdf` | `:pdf`, `:png`, `:svg`, `:html` |
| `output` | `nil` | Write to file path |
| `ppi` | `144` | PNG resolution |
| `pages` | all | Page range (`"1-5"`, `"1"`) |
| `root` | `.` | Root directory for imports |
| `font_paths` | `[]` | Additional font directories |
| `input` | `%{}` | Template variables |

---

## Template Variables

```elixir
# In Typst: #sys.inputs.title
{:ok, pdf} = OmTypst.compile("template.typ",
  input: %{title: "My Report", date: "2024-01-15", author: "Alice"}
)
```

---

## Query API

```elixir
# Extract metadata
{:ok, meta} = OmTypst.query("doc.typ", "<title>")
{:ok, headings} = OmTypst.query("doc.typ", "heading")
```

---

## Font Management

```elixir
{:ok, fonts} = OmTypst.fonts()
{:ok, fonts} = OmTypst.fonts(font_paths: ["/path/to/fonts"])
```

---

## Watch Mode

```elixir
{:ok, pid} = OmTypst.watch("doc.typ", output: "doc.pdf")
OmTypst.stop_watch(pid)
```
