[![Hex.pm](https://img.shields.io/hexpm/v/redlines)](https://hex.pm/packages/redlines)
[![Hexdocs.pm](https://img.shields.io/badge/docs-hexdocs.pm-purple)](https://hexdocs.pm/redlines)
[![Github.com](https://github.com/EnaiaInc/redlines/actions/workflows/ci.yml/badge.svg)](https://github.com/EnaiaInc/redlines/actions)

# Redlines

Extract and normalize tracked changes ("redlines") from DOC, DOCX, and PDF documents into a single unified shape.

Each format is handled by a dedicated backend:

- **DOC** — legacy Word binary format, parsed by [`doc_redlines`](https://hex.pm/packages/doc_redlines) (precompiled Rust NIF).
- **DOCX** — Office Open XML, parsed in pure Elixir by reading `word/document.xml` from the zip and extracting `<w:ins>` / `<w:del>` via `SweetXml`.
- **PDF** — parsed by [`pdf_redlines`](https://hex.pm/packages/pdf_redlines) (precompiled Rust/MuPDF NIF), which detects strikethroughs and underlines drawn over text.

All results are normalized into `Redlines.Change` structs regardless of source format. Neither Rust NIF requires a local Rust toolchain — precompiled binaries are fetched from GitHub Releases.

## Installation

Add `:redlines` to your dependencies:

```elixir
def deps do
  [
    {:redlines, "~> 0.9.2"}
  ]
end
```

`doc_redlines` and `pdf_redlines` are pulled in transitively; both ship precompiled NIFs, so no Rust toolchain is required.

## Usage

### Extracting Changes

```elixir
# DOC — legacy Word binary format (delegates to doc_redlines)
{:ok, %Redlines.Result{changes: changes, source: :doc}} =
  Redlines.extract("contract_v2.doc")

# DOCX — extracts <w:ins> and <w:del> from word/document.xml
{:ok, %Redlines.Result{changes: changes, source: :docx}} =
  Redlines.extract("contract_v2.docx")

# PDF — detects strikethrough/underline markup (delegates to pdf_redlines)
{:ok, %Redlines.Result{changes: changes, source: :pdf}} =
  Redlines.extract("contract_v2.pdf")

# Override type inference
{:ok, result} = Redlines.extract("document.bin", type: :docx)

# Forward tuning options to pdf_redlines
{:ok, result} = Redlines.extract("scan.pdf", pdf_opts: [red_r_min: 150])
```

Type is inferred from the file extension (`.doc`, `.docx`, `.pdf`); pass `:type` to override.

### Accepting DOCX Track Changes

Four variants, covering path-vs-binary input and with/without warnings about other revision markup (moves, `*PrChange` property-change history):

```elixir
# Path input
{:ok, cleaned_docx} = Redlines.clean_docx("contract_v2.docx")
{:ok, cleaned_docx, warnings} = Redlines.clean_docx_with_warnings("contract_v2.docx")

# Binary input
{:ok, cleaned_docx} = Redlines.clean_docx_binary(docx_bytes)
{:ok, cleaned_docx, warnings} = Redlines.clean_docx_binary_with_warnings(docx_bytes)
```

The cleaner removes `<w:del>…</w:del>`, unwraps `<w:ins>…</w:ins>`, and drops other WordprocessingML revision markup where possible. DOC and PDF do not have analogous cleaners — accepting tracked changes is a DOCX-only operation.

### The Change Struct

Every tracked change is normalized into a `Redlines.Change`:

```elixir
%Redlines.Change{
  type: :deletion | :insertion | :paired,
  deletion: "removed text" | nil,
  insertion: "added text" | nil,
  location: "page 3, paragraph 2" | nil,
  meta: %{"source" => "docx" | "doc" | "pdf", ...}
}
```

- `:deletion` — text was removed (`deletion` populated)
- `:insertion` — text was added (`insertion` populated)
- `:paired` — a deletion and insertion representing a replacement (both populated)

`meta` varies by source:

| Source | Keys |
| ------ | ---- |
| `"doc"`  | `author`, `timestamp` (ISO-8601), `paragraph_index`, `char_offset`, `context` |
| `"docx"` | `id`, `author`, `date` |
| `"pdf"`  | (none beyond `source`) |

DOC and PDF may emit `:paired` changes; DOCX only emits `:insertion` and `:deletion`.

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

- `:pair_separator` — separator between deleted/inserted pairs (default `"→"`)
- `:max_len` — truncation length for long text (default `150`)

Accepts a `Redlines.Result`, a list of `Redlines.Change` structs, a raw DOCX track-changes map (`%{insertions: [...], deletions: [...]}`), or a list of `pdf_redlines` entries.

## Performance

- **DOC** — Rust NIF on a dirty scheduler; typical documents complete in tens of milliseconds.
- **DOCX** — pure Elixir XML parsing; effectively instant.
- **PDF** — Rust/MuPDF NIF on a dirty scheduler; under 700 ms even on 35 MB scanned PDFs.

## License

MIT — see [LICENSE](LICENSE).
