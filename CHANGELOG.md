# Changelog

## 0.7.1

- DOCX cleaning now also accepts moved text (`<w:moveFrom>`, `<w:moveTo>`) and drops revision history/markers (e.g. `*PrChange`, `*RangeStart/*RangeEnd`).
- Added warning-returning helpers: `Redlines.clean_docx_with_warnings/2`, `Redlines.clean_docx_binary_with_warnings/2`.

## 0.7.0

- Added DOCX cleaning helpers to accept track changes (remove `<w:del>` and unwrap `<w:ins>`) and return a cleaned DOCX: `Redlines.clean_docx/2`, `Redlines.clean_docx_binary/2`.

## 0.6.1

- Bump `pdf_redlines` to `~> 0.7.1` (fixes precompiled NIF checksum mismatch)

## 0.6.0

- **Breaking:** Removed `has_redlines?/1`. Callers should use `extract/2` and check `result.changes == []` instead. The old heuristic pre-check doubled the PDF rendering cost and risked false negatives on non-standard redline colors.
- Bumped `pdf_redlines` to `~> 0.7.0`.
- Added performance section to README (under 700 ms on 35 MB+ scanned documents).

## 0.5.1

- Bump `pdf_redlines` dependency to `~> 0.6.3`

## 0.5.0

- `pdf_redlines` is now a required dependency (precompiled NIF, no toolchain needed).
- Removed runtime detection of `PDFRedlines` module availability.
- Expanded README with badges, full API docs, and usage examples.

## 0.1.0

- Initial release.
- DOCX track-changes extraction from `word/document.xml`.
- Optional PDF extraction via the `pdf_redlines` package.
- Unified `Redlines.Change` shape and `Redlines.format_for_llm/1`.
