defmodule Redlines.DOCXTest do
  use ExUnit.Case, async: true

  alias Redlines.{Change, DOCX}

  test "extracts insertions and deletions from DOCX document.xml" do
    xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:ins w:id="1" w:author="Alice" w:date="2026-02-01T00:00:00Z">
            <w:r><w:t>Inserted Content</w:t></w:r>
          </w:ins>
          <w:del w:id="2" w:author="Bob" w:date="2026-02-02T00:00:00Z">
            <w:r><w:delText>Deleted Content</w:delText></w:r>
          </w:del>
        </w:p>
      </w:body>
    </w:document>
    """

    docx_path = build_docx_with_document_xml!(xml)

    assert {:ok, %{insertions: ins, deletions: del}} = DOCX.extract_track_changes(docx_path)
    assert length(ins) == 1
    assert length(del) == 1

    changes = DOCX.to_changes(%{insertions: ins, deletions: del})

    assert [
             %Change{type: :insertion, insertion: "Inserted Content"},
             %Change{type: :deletion, deletion: "Deleted Content"}
           ] = Enum.map(changes, &strip_meta/1)
  end

  defp strip_meta(%Change{} = c), do: %{c | meta: %{}, location: nil}

  defp build_docx_with_document_xml!(document_xml) when is_binary(document_xml) do
    base = Path.join(System.tmp_dir!(), "redlines_docx_#{System.unique_integer([:positive])}")
    File.mkdir_p!(base)

    path = Path.join(base, "test.docx")

    entries = [
      {~c"word/document.xml", document_xml}
    ]

    {:ok, _} = :zip.create(String.to_charlist(path), entries, [])
    path
  end
end
