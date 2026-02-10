defmodule Redlines.DOCXCleanTest do
  use ExUnit.Case, async: true

  alias Redlines.DOCX

  test "clean/2 accepts insertions and removes deletions in word/document.xml" do
    xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:r><w:t>Keep</w:t></w:r>
          <w:ins w:id="1" w:author="Alice" w:date="2026-02-01T00:00:00Z">
            <w:r><w:t>Inserted &amp; Content</w:t></w:r>
          </w:ins>
          <w:del w:id="2" w:author="Bob" w:date="2026-02-02T00:00:00Z">
            <w:r><w:delText>Deleted Content</w:delText></w:r>
          </w:del>
        </w:p>
      </w:body>
    </w:document>
    """

    other_xml = "<root>unchanged</root>"

    docx_path =
      build_docx_with_entries!([
        {~c"word/document.xml", xml},
        {~c"word/other.xml", other_xml}
      ])

    assert {:ok, cleaned_docx} = DOCX.clean(docx_path)

    {:ok, entries} = :zip.unzip(cleaned_docx, [:memory])

    {_name, cleaned_document_xml} =
      Enum.find(entries, fn {name, _content} -> name == ~c"word/document.xml" end)

    {_name, cleaned_other_xml} =
      Enum.find(entries, fn {name, _content} -> name == ~c"word/other.xml" end)

    assert cleaned_document_xml =~ "Keep"
    assert cleaned_document_xml =~ "Inserted &amp; Content"

    assert cleaned_document_xml =~
             "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""

    refute cleaned_document_xml =~ "<w:ins"
    refute cleaned_document_xml =~ "</w:ins>"
    refute cleaned_document_xml =~ "<w:del"
    refute cleaned_document_xml =~ "Deleted Content"

    # Ensure we didn't produce broken namespace/prefix output.
    assert {_doc, _rest} =
             :xmerl_scan.string(String.to_charlist(cleaned_document_xml),
               namespace_conformant: true
             )

    assert cleaned_other_xml == other_xml
  end

  defp build_docx_with_entries!(entries) when is_list(entries) do
    base =
      Path.join(System.tmp_dir!(), "redlines_docx_clean_#{System.unique_integer([:positive])}")

    File.mkdir_p!(base)

    path = Path.join(base, "test.docx")
    {:ok, _} = :zip.create(String.to_charlist(path), entries, [])
    path
  end
end
