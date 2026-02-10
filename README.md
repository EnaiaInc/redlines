[![Hex.pm](https://img.shields.io/hexpm/v/redlines)](https://hex.pm/packages/redlines)
[![Hexdocs.pm](https://img.shields.io/badge/docs-hexdocs.pm-purple)](https://hexdocs.pm/redlines)
[![Github.com](https://github.com/EnaiaInc/redlines/actions/workflows/ci.yml/badge.svg)](https://github.com/EnaiaInc/redlines/actions)

# Redlines

Extract and normalize tracked changes ("redlines") from DOCX and PDF documents into a single unified shape.

Redlines parses `<w:ins>` and `<w:del>` elements from DOCX files and uses [`pdf_redlines`](https://hex.pm/packages/pdf_redlines) (precompiled Rust/MuPDF NIF) for PDF extraction. All changes are normalized into `Redlines.Change` structs regardless of source format.

## Installation

Add `:redlines` to your dependencies:

```elixir
def deps do
  [
    {:redlines, "~> 0.7.0"}
  ]
end
```

PDF support is included out of the box via the precompiled [`pdf_redlines`](https://hex.pm/packages/pdf_redlines) NIF -- no Rust toolchain required.

## Usage

### Extracting Changes

```elixir
# DOCX - extracts <w:ins> and <w:del> from word/document.xml
{:ok, %Redlines.Result{changes: changes, source: :docx}} =
  Redlines.extract("contract_v2.docx")

# DOCX - accept track changes and get cleaned DOCX bytes
{:ok, cleaned_docx} = Redlines.clean_docx("contract_v2.docx")
File.write!("contract_v2_clean.docx", cleaned_docx)

# PDF
{:ok, %Redlines.Result{changes: changes, source: :pdf}} =
  Redlines.extract("contract_v2.pdf")

# Override type inference
{:ok, result} = Redlines.extract("document.bin", type: :docx)
```

### The Change Struct

Every tracked change is normalized into a `Redlines.Change`:

```elixir
%Redlines.Change{
  type: :deletion | :insertion | :paired,
  deletion: "removed text" | nil,
  insertion: "added text" | nil,
  location: "page 3, paragraph 2" | nil,
  meta: %{"source" => "docx", "author" => "Alice", "date" => "2026-01-15T10:00:00Z"}
}
```

- `:deletion` - Text was removed
- `:insertion` - Text was added
- `:paired` - A deletion and insertion that represent a replacement

### Formatting for LLM Prompts

`format_for_llm/2` produces a structured text summary suitable for including in LLM prompts:

```elixir
Redlines.format_for_llm(changes)
# DELETIONS (removed content):
#   - "the old clause"
#
#
# INSERTIONS (new content):
#   + "the new clause"
#
#
# DELETED → INSERTED:
#   "old term" → "new term"
```

Options:

- `:pair_separator` - Separator between deleted/inserted pairs (default `"→"`)
- `:max_len` - Truncation length for long text (default `150`)

Accepts a `Redlines.Result`, a list of `Redlines.Change` structs, a raw DOCX track-changes map, or a list of PDF redline entries.

## Performance

PDF extraction uses a precompiled Rust NIF and finishes under 700 ms even on
large scanned documents (35 MB+). DOCX parsing is pure Elixir XML and is
effectively instant.

## License

MIT - see [LICENSE](LICENSE).
