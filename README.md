# Redlines

Extract and normalize tracked changes ("redlines") from DOCX and PDFs.

## Installation

Add `:redlines` to your dependencies:

```elixir
def deps do
  [
    {:redlines, "~> 0.1.0"}
  ]
end
```

### PDF Support

PDF extraction is provided via the [`pdf_redlines`](https://hex.pm/packages/pdf_redlines) package
(Rust/MuPDF NIF). To enable it, add:

```elixir
{:pdf_redlines, "~> 0.6"}
```

## Usage

```elixir
# DOCX
{:ok, %Redlines.Result{changes: changes, source: :docx}} =
  Redlines.extract("/path/to/document.docx")

# PDF (requires :pdf_redlines)
{:ok, %Redlines.Result{changes: changes, source: :pdf}} =
  Redlines.extract("/path/to/document.pdf")

# Format for prompts
formatted = Redlines.format_for_llm(changes)
```
