defmodule Redlines.Format do
  @moduledoc """
  Formatting helpers.
  """

  alias Redlines.{Change, DOCX, PDF, Result}

  @default_pair_separator "→"
  @default_max_len 150

  @doc """
  Format tracked changes for LLM prompts.

  Returns `""` for empty inputs.

  ## Options

  - `:pair_separator` - Default `"→"`
  - `:max_len` - Truncation length, default `150`
  """
  @spec format_for_llm(Result.t() | [Change.t()] | map() | list(), keyword()) :: String.t()
  def format_for_llm(input, opts \\ []) do
    changes = normalize_to_changes(input)

    if changes == [] do
      ""
    else
      pair_separator = Keyword.get(opts, :pair_separator, @default_pair_separator)
      max_len = Keyword.get(opts, :max_len, @default_max_len)

      grouped = Enum.group_by(changes, & &1.type)

      parts =
        []
        |> maybe_add_group(
          :deletion,
          "DELETIONS (removed content):",
          grouped,
          max_len,
          fn %Change{} = c ->
            c.deletion
          end,
          fn text -> "  - \"#{text}\"" end
        )
        |> maybe_add_group(
          :insertion,
          "INSERTIONS (new content):",
          grouped,
          max_len,
          fn %Change{} = c ->
            c.insertion
          end,
          fn text -> "  + \"#{text}\"" end
        )
        |> maybe_add_pairs(grouped, pair_separator, max_len)

      Enum.join(parts, "\n") <> "\n"
    end
  end

  defp maybe_add_group(parts, type, title, grouped, max_len, text_fun, line_fun) do
    entries =
      grouped
      |> Map.get(type, [])
      |> Enum.map(text_fun)
      |> Enum.map(&truncate(&1, max_len))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if entries == [] do
      parts
    else
      parts =
        if parts == [] do
          parts
        else
          parts ++ ["", ""]
        end

      parts ++ [title] ++ Enum.map(entries, line_fun)
    end
  end

  defp maybe_add_pairs(parts, grouped, pair_separator, max_len) do
    pairs =
      grouped
      |> Map.get(:paired, [])
      |> Enum.map(fn %Change{} = c ->
        del = c.deletion |> truncate(max_len) |> String.trim()
        ins = c.insertion |> truncate(max_len) |> String.trim()
        format_paired(del, ins, pair_separator)
      end)
      |> Enum.reject(&(&1 == ""))

    if pairs == [] do
      parts
    else
      parts =
        if parts == [] do
          parts
        else
          parts ++ ["", ""]
        end

      parts ++ ["DELETED #{pair_separator} INSERTED:"] ++ pairs
    end
  end

  defp format_paired("", "", _sep), do: ""
  defp format_paired(del, "", sep), do: "  \"#{del}\" #{sep} (nothing)"
  defp format_paired("", ins, sep), do: "  (nothing) #{sep} \"#{ins}\""
  defp format_paired(del, ins, sep), do: "  \"#{del}\" #{sep} \"#{ins}\""

  defp truncate(text, max_len) when is_binary(text) do
    text = String.trim(text)

    if String.length(text) > max_len do
      # Keep room for "..."
      String.slice(text, 0, max_len - 3) <> "..."
    else
      text
    end
  end

  defp truncate(_text, _max_len), do: ""

  defp normalize_to_changes(%Result{changes: changes}) when is_list(changes), do: changes

  defp normalize_to_changes(changes) when is_list(changes) do
    if Enum.all?(changes, &match?(%Change{}, &1)) do
      changes
    else
      PDF.to_changes(changes)
    end
  end

  defp normalize_to_changes(%{insertions: _ins, deletions: _del} = docx_track_changes) do
    DOCX.to_changes(docx_track_changes)
  end

  defp normalize_to_changes(_), do: []
end
