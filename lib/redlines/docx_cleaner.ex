defmodule Redlines.DOCX.Cleaner do
  @moduledoc false

  # WordprocessingML namespace
  @w_ns ~c"http://schemas.openxmlformats.org/wordprocessingml/2006/main"

  @type ns_mapping :: {prefix :: charlist(), uri :: charlist()}
  @type warning :: %{
          required(:type) => :other_revision_markup,
          required(:element) => String.t(),
          required(:count) => non_neg_integer()
        }

  @spec accept_tracked_changes_xml(binary()) :: {:ok, binary()} | {:error, term()}
  def accept_tracked_changes_xml(xml) when is_binary(xml) do
    case do_accept_tracked_changes_xml(xml, :no_warnings) do
      {:ok, cleaned_xml, _warnings} -> {:ok, cleaned_xml}
      {:error, _} = error -> error
    end
  end

  @spec accept_tracked_changes_xml_with_warnings(binary()) ::
          {:ok, binary(), [warning()]} | {:error, term()}
  def accept_tracked_changes_xml_with_warnings(xml) when is_binary(xml) do
    case do_accept_tracked_changes_xml(xml, :with_warnings) do
      {:ok, cleaned_xml, warnings} -> {:ok, cleaned_xml, warnings}
      {:error, _} = error -> error
    end
  end

  defp do_accept_tracked_changes_xml(xml, warning_mode) when is_binary(xml) do
    prolog = extract_xml_prolog(xml)

    initial_state = %{
      skip_depth: 0,
      pending_ns: [],
      # Namespace mappings declared on elements we suppress (e.g. <w:ins>) need
      # to be re-declared somewhere in the output. We conservatively re-declare
      # them on every element we DO emit while they are in-scope.
      orphan_ns: [],
      in_cdata: false,
      out: [],
      rev_counts: %{},
      warning_mode: warning_mode
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

        {:ok, prolog <> body, build_warnings(state)}

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
  def handle_event(:startDocument, _loc, state), do: state
  def handle_event(:endDocument, _loc, state), do: state

  def handle_event({:startPrefixMapping, prefix, uri}, _loc, state) do
    # These mappings belong to the *next* startElement event.
    %{state | pending_ns: [{prefix, uri} | state.pending_ns]}
  end

  def handle_event({:endPrefixMapping, prefix}, _loc, state) do
    # Only orphan mappings are tracked here; regular mappings were already
    # emitted on their original element.
    %{state | orphan_ns: pop_orphan_ns(state.orphan_ns, prefix)}
  end

  def handle_event({:startElement, uri, local, qname, attrs}, _loc, state),
    do: handle_start_element(uri, local, qname, attrs, state)

  def handle_event({:endElement, uri, local, qname}, _loc, state),
    do: handle_end_element(uri, local, qname, state)

  def handle_event({:characters, chars}, _loc, state),
    do: handle_characters(chars, state)

  def handle_event({:ignorableWhitespace, chars}, _loc, state),
    do: handle_characters(chars, state)

  def handle_event({:processingInstruction, target, data}, _loc, state),
    do: handle_processing_instruction(target, data, state)

  def handle_event({:comment, comment}, _loc, state),
    do: handle_comment(comment, state)

  def handle_event(:startCDATA, _loc, state),
    do: handle_start_cdata(state)

  def handle_event(:endCDATA, _loc, state),
    do: handle_end_cdata(state)

  def handle_event(_other, _loc, state), do: state

  defp handle_start_element(uri, local, qname, attrs, state) do
    # Always clear pending_ns; it is only for the immediately following element.
    pending_ns = Enum.reverse(state.pending_ns)
    state = %{state | pending_ns: []}

    local_str = to_string(local)
    state = maybe_track_revision_element(uri, local_str, state)

    cond do
      # If we're already skipping, stay in skip mode. Track nesting of "skipper" elements.
      state.skip_depth > 0 ->
        if skipper_element?(uri, local_str) do
          %{state | skip_depth: state.skip_depth + 1}
        else
          state
        end

      # Elements whose content should be deleted when accepting revisions.
      delete_wrapper_element?(uri, local_str) ->
        %{state | skip_depth: state.skip_depth + 1}

      # Elements that record revision history (e.g., formatting changes) or
      # revision markers (e.g., range boundaries) that we drop.
      purge_revision_element?(uri, local_str) ->
        %{state | skip_depth: state.skip_depth + 1}

      # Elements whose content should be kept, but whose wrapper tag should be removed.
      unwrap_element?(uri, local_str) ->
        orphan_ns = state.orphan_ns ++ pending_ns
        %{state | orphan_ns: orphan_ns}

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
    local_str = to_string(local)

    cond do
      # While skipping, suppress everything but keep nesting balanced.
      state.skip_depth > 0 ->
        if skipper_element?(uri, local_str) do
          %{state | skip_depth: max(state.skip_depth - 1, 0)}
        else
          state
        end

      unwrap_element?(uri, local_str) ->
        state

      true ->
        name = qname_to_string(qname)
        %{state | out: ["</" <> name <> ">" | state.out]}
    end
  end

  defp handle_characters(chars, state) do
    if state.skip_depth > 0 do
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

  defp handle_processing_instruction(_target, _data, %{skip_depth: d} = state) when d > 0,
    do: state

  defp handle_processing_instruction(target, data, state) do
    pi = "<?" <> to_string(target) <> " " <> to_string(data) <> "?>"
    %{state | out: [pi | state.out]}
  end

  defp handle_comment(_comment, %{skip_depth: d} = state) when d > 0, do: state

  defp handle_comment(comment, state) do
    c = "<!--" <> to_string(comment) <> "-->"
    %{state | out: [c | state.out]}
  end

  defp handle_start_cdata(%{skip_depth: d} = state) when d > 0, do: state
  defp handle_start_cdata(state), do: %{state | in_cdata: true, out: ["<![CDATA[" | state.out]}

  defp handle_end_cdata(%{skip_depth: d} = state) when d > 0, do: state
  defp handle_end_cdata(state), do: %{state | in_cdata: false, out: ["]]>" | state.out]}

  defp delete_wrapper_element?(uri, local_str) do
    uri == @w_ns and local_str in ["del", "moveFrom"]
  end

  defp unwrap_element?(uri, local_str) do
    uri == @w_ns and local_str in ["ins", "moveTo"]
  end

  defp purge_revision_element?(uri, local_str) do
    uri == @w_ns and (String.ends_with?(local_str, "Change") or revision_range_marker?(local_str))
  end

  defp revision_range_marker?(local_str) do
    down = String.downcase(local_str)

    (String.ends_with?(down, "rangestart") or String.ends_with?(down, "rangeend")) and
      (String.contains?(down, "ins") or String.contains?(down, "del") or
         String.contains?(down, "movefrom") or String.contains?(down, "moveto"))
  end

  defp skipper_element?(uri, local_str) do
    delete_wrapper_element?(uri, local_str) or purge_revision_element?(uri, local_str)
  end

  defp maybe_track_revision_element(uri, local_str, state) do
    if revision_related?(uri, local_str) do
      counts = Map.update(state.rev_counts, local_str, 1, &(&1 + 1))
      %{state | rev_counts: counts}
    else
      state
    end
  end

  defp revision_related?(uri, local_str) do
    uri == @w_ns and
      (local_str in ["ins", "del", "moveFrom", "moveTo"] or String.ends_with?(local_str, "Change") or
         revision_range_marker?(local_str))
  end

  defp build_warnings(%{warning_mode: :no_warnings}), do: []

  defp build_warnings(%{warning_mode: :with_warnings, rev_counts: counts}) do
    counts
    |> Enum.reject(fn {k, _v} -> k in ["ins", "del"] end)
    |> Enum.sort_by(fn {_k, v} -> -v end)
    |> Enum.map(fn {k, v} ->
      %{type: :other_revision_markup, element: "w:" <> k, count: v}
    end)
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
