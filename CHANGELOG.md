# Changelog

## 0.5.0

- `pdf_redlines` is now a required dependency (precompiled NIF, no toolchain needed).
- Removed runtime detection of `PDFRedlines` module availability.
- Expanded README with badges, full API docs, and usage examples.

## 0.1.0

- Initial release.
- DOCX track-changes extraction from `word/document.xml`.
- Optional PDF extraction via the `pdf_redlines` package.
- Unified `Redlines.Change` shape and `Redlines.format_for_llm/1`.
