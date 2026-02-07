defmodule Redlines.FormatTest do
  use ExUnit.Case, async: true

  alias Redlines.Change

  test "formats grouped deletions/insertions/paired for prompts" do
    changes = [
      %Change{type: :deletion, deletion: "3"},
      %Change{type: :insertion, insertion: "Bradley Product"},
      %Change{type: :paired, deletion: "October 9", insertion: "October 3"}
    ]

    expected = """
    DELETIONS (removed content):
      - "3"


    INSERTIONS (new content):
      + "Bradley Product"


    DELETED → INSERTED:
      "October 9" → "October 3"
    """

    assert expected == Redlines.format_for_llm(changes)
  end

  test "empty input formats to empty string" do
    assert "" == Redlines.format_for_llm([])
  end
end
