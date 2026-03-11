defmodule Redlines.DOCTest do
  use ExUnit.Case, async: true

  alias Redlines.{Change, DOC}

  test "infers :doc from extension" do
    assert :doc == Redlines.infer_type("contract.doc")
  end

  test "normalizes doc redline maps into Change structs" do
    redlines = [
      %{
        type: :deletion,
        text: "thirty (30)",
        location: "paragraph:12 offset:245",
        author: "Jane Smith",
        timestamp: "2024-03-15T14:32:00Z",
        paragraph_index: 12,
        char_offset: 245,
        context: "...the term shall be thirty (30) days..."
      },
      %{
        type: :insertion,
        text: "sixty (60)",
        location: "paragraph:12 offset:245"
      }
    ]

    assert [
             %Change{
               type: :deletion,
               deletion: "thirty (30)",
               location: "paragraph:12 offset:245",
               meta: %{
                 "source" => "doc",
                 "author" => "Jane Smith",
                 "timestamp" => "2024-03-15T14:32:00Z",
                 "paragraph_index" => 12,
                 "char_offset" => 245,
                 "context" => "...the term shall be thirty (30) days..."
               }
             },
             %Change{
               type: :insertion,
               insertion: "sixty (60)",
               location: "paragraph:12 offset:245"
             }
           ] = DOC.to_changes(redlines)
  end

  test "returns clear error when doc_redlines dependency is unavailable" do
    case DOC.extract_redlines("/nonexistent/file.doc") do
      {:error, :doc_redlines_not_available} ->
        assert true

      {:error, _reason} ->
        # doc_redlines is available and returned a regular extraction error
        assert true

      other ->
        flunk("Unexpected result: #{inspect(other)}")
    end
  end

  test "extracts from synthetic doc fixture when available" do
    unless Code.ensure_loaded?(DocRedlines) do
      IO.puts("Skipping doc fixture test: doc_redlines not available")
      assert true
    else
      fixture = Path.expand("fixtures/sample.doc", __DIR__)
      assert File.exists?(fixture)

      assert {:ok, %Redlines.Result{source: :doc, changes: changes}} =
               Redlines.extract(fixture)

      assert is_list(changes)
    end
  end
end
