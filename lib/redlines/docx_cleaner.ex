defmodule Redlines.DOCX.Cleaner do
  @moduledoc false

  # WordprocessingML namespace
  @w_ns ~c"http://schemas.openxmlformats.org/wordprocessingml/2006/main"

  @type ns_mapping :: {prefix :: charlist(), uri :: charlist()}

  @spec accept_tracked_changes_xml(binary()) :: {:ok, binary()} | {:error, term()}
  def accept_tracked_changes_xml(xml) when is_binary(xml) do
    prolog = extract_xml_prolog(xml)

    initial_state = %{
      skip_del_depth: 0,
      unwrap_ins_depth: 0,
      pending_ns: [],
      # Namespace mappings declared on elements we suppress (e.g. <w:ins>) need
      # to be re-declared somewhere in the output. We conservatively re-declare
      # them on every element we DO emit while they are in-scope.
      orphan_ns: [],
      in_cdata: false,
      out: []
    }

    opts = [
      :skip_external_dtd,
      event_state: initial_state,
      event_fun: &__MODULE__.handle_event/3,
      discard_ws_before_xml_document: true
    ]

    case :xmerl_sax_parser.stream(xml, opts) do
      {:ok, state, _rest} ->
        body =
          state.out
          |> Enum.reverse()
          |> IO.iodata_to_binary()

        {:ok, prolog <> body}

      {:fatal_error, _loc, reason, _tags, _state} ->
        {:error, {:xml_parse_error, to_string(reason)}}

      other ->
        {:error, other}
    end
  rescue
    e ->
      {:error, e}
  end

  @doc false
  def handle_event(event, _loc, state) do
    case event do
      :startDocument ->
        state

      :endDocument ->
        state

      {:startPrefixMapping, prefix, uri} ->
        # These mappings belong to the *next* startElement event.
        %{state | pending_ns: [{prefix, uri} | state.pending_ns]}

      {:endPrefixMapping, prefix} ->
        # Only orphan mappings are tracked here; regular mappings were already
        # emitted on their original element.
        %{state | orphan_ns: pop_orphan_ns(state.orphan_ns, prefix)}

      {:startElement, uri, local, qname, attrs} ->
        handle_start_element(uri, local, qname, attrs, state)

      {:endElement, uri, local, qname} ->
        handle_end_element(uri, local, qname, state)

      {:characters, chars} ->
        handle_characters(chars, state)

      {:ignorableWhitespace, chars} ->
        handle_characters(chars, state)

      {:processingInstruction, target, data} ->
        if state.skip_del_depth > 0 do
          state
        else
          pi = "<?" <> to_string(target) <> " " <> to_string(data) <> "?>"
          %{state | out: [pi | state.out]}
        end

      {:comment, comment} ->
        if state.skip_del_depth > 0 do
          state
        else
          c = "<!--" <> to_string(comment) <> "-->"
          %{state | out: [c | state.out]}
        end

      :startCDATA ->
        if state.skip_del_depth > 0 do
          state
        else
          %{state | in_cdata: true, out: ["<![CDATA[" | state.out]}
        end

      :endCDATA ->
        if state.skip_del_depth > 0 do
          state
        else
          %{state | in_cdata: false, out: ["]]>" | state.out]}
        end

      _other ->
        state
    end
  end

  defp handle_start_element(uri, local, qname, attrs, state) do
    # Always clear pending_ns; it is only for the immediately following element.
    pending_ns = Enum.reverse(state.pending_ns)
    state = %{state | pending_ns: []}

    cond do
      # If we're already skipping deletions, just keep skipping. Track nesting.
      state.skip_del_depth > 0 ->
        if w_element?(uri, local, ~c"del") do
          %{state | skip_del_depth: state.skip_del_depth + 1}
        else
          state
        end

      # Start skipping a deletion subtree entirely.
      w_element?(uri, local, ~c"del") ->
        %{state | skip_del_depth: state.skip_del_depth + 1}

      # Unwrap insertions: drop the <w:ins> tag but keep its children.
      w_element?(uri, local, ~c"ins") ->
        orphan_ns = state.orphan_ns ++ pending_ns
        %{state | unwrap_ins_depth: state.unwrap_ins_depth + 1, orphan_ns: orphan_ns}

      true ->
        # For normal elements, emit a start tag and re-declare any "orphaned"
        # namespace mappings (declared on suppressed elements) so the output
        # remains namespace-correct.
        xmlns_ns = pending_ns ++ orphan_ns_to_emit(state.orphan_ns, pending_ns)
        tag = build_open_tag(qname, attrs, xmlns_ns)
        %{state | out: [tag | state.out]}
    end
  end

  defp handle_end_element(uri, local, qname, state) do
    cond do
      # While skipping deletions, suppress everything but keep nesting balanced.
      state.skip_del_depth > 0 ->
        if w_element?(uri, local, ~c"del") do
          %{state | skip_del_depth: max(state.skip_del_depth - 1, 0)}
        else
          state
        end

      w_element?(uri, local, ~c"del") ->
        %{state | skip_del_depth: max(state.skip_del_depth - 1, 0)}

      w_element?(uri, local, ~c"ins") ->
        %{state | unwrap_ins_depth: max(state.unwrap_ins_depth - 1, 0)}

      true ->
        name = qname_to_string(qname)
        %{state | out: ["</" <> name <> ">" | state.out]}
    end
  end

  defp handle_characters(chars, state) do
    if state.skip_del_depth > 0 do
      state
    else
      bin = to_string(chars)

      out =
        if state.in_cdata do
          bin
        else
          escape_text(bin)
        end

      %{state | out: [out | state.out]}
    end
  end

  defp w_element?(uri, local, expected_local) do
    uri == @w_ns and local == expected_local
  end

  defp orphan_ns_to_emit(orphan_ns, pending_ns) do
    pending_prefixes = MapSet.new(Enum.map(pending_ns, &elem(&1, 0)))

    orphan_ns
    |> Enum.reverse()
    |> Enum.reduce({MapSet.new(), []}, fn {prefix, _uri} = m, {seen, acc} ->
      cond do
        MapSet.member?(pending_prefixes, prefix) ->
          {seen, acc}

        MapSet.member?(seen, prefix) ->
          {seen, acc}

        true ->
          {MapSet.put(seen, prefix), [m | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp pop_orphan_ns(orphan_ns, prefix) do
    # endPrefixMapping doesn't include the uri, so treat this like a stack
    # pop for that prefix (remove the most-recent mapping for this prefix).
    orphan_ns
    |> Enum.reverse()
    |> Enum.reduce({[], false}, fn {p, _uri} = m, {acc, dropped?} ->
      cond do
        dropped? ->
          {[m | acc], true}

        p == prefix ->
          {acc, true}

        true ->
          {[m | acc], false}
      end
    end)
    |> elem(0)
  end

  defp build_open_tag(qname, attrs, xmlns_ns) do
    name = qname_to_string(qname)

    xmlns_attrs =
      Enum.map(xmlns_ns, fn {prefix, uri} ->
        prefix_str = to_string(prefix)
        uri_str = escape_attr(to_string(uri))

        attr_name =
          if prefix_str == "" do
            "xmlns"
          else
            "xmlns:" <> prefix_str
          end

        attr_name <> "=\"" <> uri_str <> "\""
      end)

    normal_attrs =
      Enum.map(attrs, fn {_uri, prefix, local, value} ->
        prefix_str = to_string(prefix)
        local_str = to_string(local)

        attr_name =
          if prefix_str == "" do
            local_str
          else
            prefix_str <> ":" <> local_str
          end

        attr_name <> "=\"" <> escape_attr(to_string(value)) <> "\""
      end)

    attrs_strs = xmlns_attrs ++ normal_attrs

    if attrs_strs == [] do
      "<" <> name <> ">"
    else
      "<" <> name <> " " <> Enum.join(attrs_strs, " ") <> ">"
    end
  end

  defp qname_to_string({prefix, local}) do
    prefix_str = to_string(prefix)
    local_str = to_string(local)

    if prefix_str == "" do
      local_str
    else
      prefix_str <> ":" <> local_str
    end
  end

  defp escape_text(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(text) when is_binary(text) do
    text
    |> escape_text()
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp extract_xml_prolog(xml) when is_binary(xml) do
    case Regex.run(~r/\\A\\s*<\\?xml.*?\\?>\\s*/s, xml) do
      [decl] -> decl
      _ -> ""
    end
  end
end
