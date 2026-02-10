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

  test "clean_binary/2 does not leak deleted text when <w:del> tags are nested/malformed" do
    xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:r><w:t>Keep</w:t></w:r>
          <w:del>
            <w:r><w:delText>OUTER1</w:delText></w:r>
            <w:del>
              <w:r><w:delText>INNER</w:delText></w:r>
            </w:del>
            <w:r><w:delText>OUTER2</w:delText></w:r>
          </w:del>
          <w:ins><w:r><w:t>Inserted</w:t></w:r></w:ins>
        </w:p>
      </w:body>
    </w:document>
    """

    docx_binary = build_docx_binary_with_entries!([{~c"word/document.xml", xml}])

    assert {:ok, cleaned_docx} = DOCX.clean_binary(docx_binary)

    {:ok, entries} = :zip.unzip(cleaned_docx, [:memory])

    {_name, cleaned_document_xml} =
      Enum.find(entries, fn {name, _content} -> name == ~c"word/document.xml" end)

    refute cleaned_document_xml =~ "<w:del"
    refute cleaned_document_xml =~ "OUTER1"
    refute cleaned_document_xml =~ "INNER"
    refute cleaned_document_xml =~ "OUTER2"

    assert cleaned_document_xml =~ "Keep"
    assert cleaned_document_xml =~ "Inserted"

    assert {_doc, _rest} =
             :xmerl_scan.string(String.to_charlist(cleaned_document_xml),
               namespace_conformant: true
             )
  end

  test "clean_binary/2 drops property-change revision history (e.g. w:rPrChange)" do
    xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:r>
            <w:rPr>
              <w:b/>
              <w:rPrChange w:id="3">
                <w:rPr><w:i/></w:rPr>
              </w:rPrChange>
            </w:rPr>
            <w:t>Keep</w:t>
          </w:r>
        </w:p>
      </w:body>
    </w:document>
    """

    docx_binary = build_docx_binary_with_entries!([{~c"word/document.xml", xml}])

    assert {:ok, cleaned_docx} = DOCX.clean_binary(docx_binary)

    {:ok, entries} = :zip.unzip(cleaned_docx, [:memory])

    {_name, cleaned_document_xml} =
      Enum.find(entries, fn {name, _content} -> name == ~c"word/document.xml" end)

    assert cleaned_document_xml =~ "Keep"
    refute cleaned_document_xml =~ "rPrChange"
  end

  test "clean_binary/2 accepts moves (w:moveFrom/w:moveTo) and drops range markers" do
    xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:moveFromRangeStart w:id="1"/>
          <w:moveToRangeStart w:id="1"/>
          <w:moveFrom>
            <w:r><w:delText>Moved From</w:delText></w:r>
          </w:moveFrom>
          <w:moveTo>
            <w:r><w:t>Moved To</w:t></w:r>
          </w:moveTo>
          <w:moveFromRangeEnd w:id="1"/>
          <w:moveToRangeEnd w:id="1"/>
        </w:p>
      </w:body>
    </w:document>
    """

    docx_binary = build_docx_binary_with_entries!([{~c"word/document.xml", xml}])

    assert {:ok, cleaned_docx} = DOCX.clean_binary(docx_binary)

    {:ok, entries} = :zip.unzip(cleaned_docx, [:memory])

    {_name, cleaned_document_xml} =
      Enum.find(entries, fn {name, _content} -> name == ~c"word/document.xml" end)

    assert cleaned_document_xml =~ "Moved To"
    refute cleaned_document_xml =~ "Moved From"
    refute cleaned_document_xml =~ "moveFrom"
    refute cleaned_document_xml =~ "moveTo"
    refute cleaned_document_xml =~ "RangeStart"
    refute cleaned_document_xml =~ "RangeEnd"
  end

  test "clean_binary_with_warnings/2 returns revision-markup counts beyond <w:ins>/<w:del>" do
    xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p>
          <w:r>
            <w:rPr>
              <w:rPrChange w:id="3">
                <w:rPr><w:i/></w:rPr>
              </w:rPrChange>
            </w:rPr>
            <w:t>Keep</w:t>
          </w:r>
        </w:p>
      </w:body>
    </w:document>
    """

    docx_binary = build_docx_binary_with_entries!([{~c"word/document.xml", xml}])

    assert {:ok, _cleaned_docx, warnings} = DOCX.clean_binary_with_warnings(docx_binary)

    assert Enum.any?(warnings, fn w ->
             w.type == :other_revision_markup and w.part == "word/document.xml" and
               w.element == "w:rPrChange" and w.count == 1
           end)
  end

  defp build_docx_with_entries!(entries) when is_list(entries) do
    base =
      Path.join(System.tmp_dir!(), "redlines_docx_clean_#{System.unique_integer([:positive])}")

    File.mkdir_p!(base)

    path = Path.join(base, "test.docx")
    {:ok, _} = :zip.create(String.to_charlist(path), entries, [])
    path
  end

  defp build_docx_binary_with_entries!(entries) when is_list(entries) do
    {:ok, {_name, bin}} = :zip.create(~c"test.docx", entries, [:memory])
    bin
  end
end
