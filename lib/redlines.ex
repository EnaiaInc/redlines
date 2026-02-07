defmodule Redlines do
  @moduledoc """
  Extract and normalize tracked changes ("redlines") from documents.

  This library provides a single normalized shape (`Redlines.Change`) across:

  - DOCX track changes (`<w:ins>`, `<w:del>`)
  - PDFs with embedded tracked-changes markup (via [`pdf_redlines`](https://hex.pm/packages/pdf_redlines))
  """

  alias Redlines.{Change, DOCX, Format, PDF, Result}

  @type doc_type :: :pdf | :docx

  @doc """
  Extract tracked changes from a file path, inferring type from the extension.

  ## Options

  - `:type` - Override the inferred type (`:pdf` or `:docx`)
  - `:pdf_opts` - Options forwarded to `PDFRedlines` (only when extracting PDFs)
  """
  @spec extract(Path.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def extract(path, opts \\ []) when is_binary(path) do
    type = Keyword.get(opts, :type, infer_type(path))

    case type do
      :docx ->
        with {:ok, track_changes} <- DOCX.extract_track_changes(path) do
          {:ok, %Result{source: :docx, changes: DOCX.to_changes(track_changes)}}
        end

      :pdf ->
        pdf_opts = Keyword.get(opts, :pdf_opts, [])

        with {:ok, redlines} <- PDF.extract_redlines(path, pdf_opts) do
          {:ok, %Result{source: :pdf, changes: PDF.to_changes(redlines)}}
        end

      other ->
        {:error, {:unsupported_type, other}}
    end
  end

  @doc """
  Check whether a file contains any tracked changes.

  For PDFs, this uses `PDFRedlines.has_redlines?/2` (fast early-exit).
  For DOCX, this parses `word/document.xml` and checks extracted changes.
  """
  @spec has_redlines?(Path.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def has_redlines?(path, opts \\ []) when is_binary(path) do
    type = Keyword.get(opts, :type, infer_type(path))

    case type do
      :pdf ->
        pdf_opts = Keyword.get(opts, :pdf_opts, [])
        PDF.has_redlines?(path, pdf_opts)

      :docx ->
        with {:ok, %Result{changes: changes}} <- extract(path, type: :docx) do
          {:ok, changes != []}
        end

      other ->
        {:error, {:unsupported_type, other}}
    end
  end

  @doc """
  Format tracked changes for LLM prompts.

  Accepts:

  - `Redlines.Result`
  - a list of `Redlines.Change`
  - a DOCX `track_changes` map (`%{insertions: [...], deletions: [...]}`)
  - a list of PDF redline structs/maps (anything with `:type`, `:deletion`, `:insertion`, `:location`)
  """
  @spec format_for_llm(Result.t() | [Change.t()] | map() | list(), keyword()) :: String.t()
  def format_for_llm(input, opts \\ []) do
    Format.format_for_llm(input, opts)
  end

  @doc false
  @spec infer_type(Path.t()) :: doc_type() | :unknown
  def infer_type(path) when is_binary(path) do
    case Path.extname(path) |> String.downcase() do
      ".pdf" -> :pdf
      ".docx" -> :docx
      _ -> :unknown
    end
  end
end
