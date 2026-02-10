defmodule Redlines.DOCXSmokeTest do
  use ExUnit.Case, async: false

  alias Redlines.DOCX

  @tag :docx_smoke
  test "clean_binary/2 can process a local DOCX corpus without leaving revision markup (optional)" do
    dir = System.get_env("REDLINES_DOCX_SMOKE_DIR")

    if dir in [nil, ""] do
      :ok
    else
      paths =
        dir
        |> Path.join("**/*.docx")
        |> Path.wildcard()
        |> Enum.sort()

      limit = parse_int_env("REDLINES_DOCX_SMOKE_LIMIT")
      paths = if is_integer(limit), do: Enum.take(paths, limit), else: paths

      # Keep a private map of index -> path for local debugging without printing
      # any filenames/content in the ExUnit output by default.
      tmp_paths =
        Path.join(
          System.tmp_dir!(),
          "redlines_docx_smoke_paths_#{System.unique_integer([:positive])}.txt"
        )

      _ =
        paths
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {p, i} -> "#{i}\t#{p}" end)
        |> then(&File.write!(tmp_paths, &1))

      Enum.with_index(paths)
      |> Enum.each(fn {path, idx} ->
        bin = File.read!(path)

        parts = discover_cleanable_parts(bin)

        case DOCX.clean_binary(bin, parts: parts) do
          {:ok, cleaned_bin} ->
            assert_cleaned_parts_have_no_revision_markup!(cleaned_bin, parts, idx)

          {:error, reason} ->
            flunk("smoke: DOCX clean failed (index=#{idx}, reason=#{inspect(reason)})")
        end
      end)
    end
  end

  defp discover_cleanable_parts(docx_bin) do
    {:ok, entries} = :zip.unzip(docx_bin, [:memory])

    entries
    |> Enum.map(fn {name, _content} -> to_string(name) end)
    |> Enum.filter(&cleanable_part?/1)
    |> case do
      [] -> ["word/document.xml"]
      parts -> parts
    end
  end

  defp cleanable_part?(part) do
    part == "word/document.xml" or
      String.starts_with?(part, "word/header") or
      String.starts_with?(part, "word/footer") or
      part in ["word/footnotes.xml", "word/endnotes.xml"]
  end

  defp assert_cleaned_parts_have_no_revision_markup!(cleaned_docx_bin, parts, idx) do
    {:ok, cleaned_entries} = :zip.unzip(cleaned_docx_bin, [:memory])

    cleaned_entries
    |> Enum.each(fn {name, content} ->
      part = to_string(name)

      if part in parts do
        # Avoid ExUnit diff output that might include document content.
        if revision_markup_present?(content) do
          flunk("smoke: cleaned XML still contains revision markup (index=#{idx}, part=#{part})")
        end
      end
    end)
  end

  defp revision_markup_present?(xml_bin) when is_binary(xml_bin) do
    # Match common tracked-change wrappers and revision markers with any prefix.
    # We keep this heuristic string-based to avoid parsing sensitive XML into error output.
    String.match?(xml_bin, ~r/<(?:[A-Za-z_][\w.-]*:)?(?:ins|del|moveFrom|moveTo)\b/) or
      String.match?(xml_bin, ~r/<(?:[A-Za-z_][\w.-]*:)?[\w.-]+Change\b/) or
      String.match?(
        xml_bin,
        ~r/<(?:[A-Za-z_][\w.-]*:)?(?:customXml)?(?:ins|del|moveFrom|moveTo)Range(?:Start|End)\b/
      )
  end

  defp parse_int_env(name) do
    case System.get_env(name) do
      nil ->
        nil

      "" ->
        nil

      v ->
        case Integer.parse(v) do
          {i, ""} -> i
          _ -> nil
        end
    end
  end
end
