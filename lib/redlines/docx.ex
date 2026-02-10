defmodule Redlines.DOCX do
  @moduledoc """
  Extract track changes from DOCX files by parsing `word/document.xml`.
  """

  alias Redlines.Change
  alias Redlines.DOCX.Cleaner

  require Logger

  @type clean_warning :: %{
          required(:type) => :revision_markup,
          required(:part) => String.t(),
          required(:element) => String.t(),
          required(:count) => non_neg_integer()
        }

  @doc """
  Extract raw DOCX track changes.

  Returns a map with `:insertions` and `:deletions`, each containing a list of
  maps with keys: `:id`, `:author`, `:date`, and `:text`.
  """
  @spec extract_track_changes(Path.t()) :: {:ok, map()} | {:error, term()}
  def extract_track_changes(docx_path) when is_binary(docx_path) do
    docx_charlist = String.to_charlist(docx_path)

    with {:ok, zip_handle} <- :zip.zip_open(docx_charlist, [:memory]),
         {:ok, {_filename, xml_content}} <- :zip.zip_get(~c"word/document.xml", zip_handle),
         :ok <- :zip.zip_close(zip_handle) do
      {:ok, parse_changes(xml_content)}
    else
      {:error, :enoent} ->
        Logger.warning("No word/document.xml found in DOCX: #{docx_path}")
        {:ok, %{deletions: [], insertions: []}}

      {:error, reason} ->
        Logger.error("Failed to read DOCX #{docx_path}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Error extracting DOCX track changes: #{Exception.message(e)}")
      {:error, e}
  end

  @doc """
  Accept tracked changes in a DOCX and return the cleaned DOCX bytes.

  This rewrites XML parts inside the DOCX zip (by default just `word/document.xml`)
  by removing deletions (`<w:del>…</w:del>`) and unwrapping insertions
  (`<w:ins>…</w:ins>`).

  ## Options

  - `:parts` - Zip entry names to clean (default `["word/document.xml"]`)
  """
  @spec clean(Path.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def clean(docx_path, opts \\ []) when is_binary(docx_path) do
    with {:ok, docx_binary} <- File.read(docx_path) do
      clean_binary(docx_binary, opts)
    end
  end

  @doc """
  Like `clean/2`, but accepts raw DOCX bytes.
  """
  @spec clean_binary(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def clean_binary(docx_binary, opts \\ []) when is_binary(docx_binary) do
    parts = Keyword.get(opts, :parts, ["word/document.xml"])
    parts_set = MapSet.new(parts)

    with {:ok, entries} <- :zip.unzip(docx_binary, [:memory]),
         {:ok, cleaned_entries} <- clean_entries(entries, parts_set),
         {:ok, {_filename, cleaned_binary}} <-
           :zip.create(~c"clean.docx", cleaned_entries, [:memory]) do
      {:ok, cleaned_binary}
    end
  rescue
    e ->
      {:error, e}
  end

  @doc """
  Like `clean/2`, but also returns informational warnings about revision markup
  that was present while cleaning.

  Each warning includes the zip `:part` (e.g. `"word/document.xml"`), an `:element`
  (e.g. `"w:rPrChange"`) and a `:count`.

  ## Options

  - `:parts` - Zip entry names to clean (default `["word/document.xml"]`)
  """
  @spec clean_with_warnings(Path.t(), keyword()) ::
          {:ok, binary(), [clean_warning()]} | {:error, term()}
  def clean_with_warnings(docx_path, opts \\ []) when is_binary(docx_path) do
    with {:ok, docx_binary} <- File.read(docx_path) do
      clean_binary_with_warnings(docx_binary, opts)
    end
  end

  @doc """
  Like `clean_binary/2`, but also returns informational warnings about revision
  markup that was present while cleaning.

  See `clean_with_warnings/2`.
  """
  @spec clean_binary_with_warnings(binary(), keyword()) ::
          {:ok, binary(), [clean_warning()]} | {:error, term()}
  def clean_binary_with_warnings(docx_binary, opts \\ []) when is_binary(docx_binary) do
    parts = Keyword.get(opts, :parts, ["word/document.xml"])
    parts_set = MapSet.new(parts)

    with {:ok, entries} <- :zip.unzip(docx_binary, [:memory]),
         {:ok, cleaned_entries, warnings} <- clean_entries_with_warnings(entries, parts_set),
         {:ok, {_filename, cleaned_binary}} <-
           :zip.create(~c"clean.docx", cleaned_entries, [:memory]) do
      {:ok, cleaned_binary, warnings}
    end
  rescue
    e ->
      {:error, e}
  end

  @doc """
  Convert a raw `%{insertions: [...], deletions: [...]}` map into normalized changes.
  """
  @spec to_changes(map()) :: [Change.t()]
  def to_changes(%{insertions: insertions, deletions: deletions})
      when is_list(insertions) and is_list(deletions) do
    insertion_changes = to_insertion_changes(insertions)
    deletion_changes = to_deletion_changes(deletions)

    # Stable order (Word revision ids are usually monotonic).
    (insertion_changes ++ deletion_changes)
    |> Enum.sort_by(&docx_id_sort_key/1)
  end

  def to_changes(_), do: []

  defp docx_id_sort_key(%Change{meta: %{"id" => id}}) when is_binary(id) do
    case Integer.parse(id) do
      {i, _} -> i
      :error -> id
    end
  end

  defp docx_id_sort_key(_), do: 0

  defp to_insertion_changes(insertions) do
    insertions
    |> Enum.map(fn m ->
      %Change{
        type: :insertion,
        insertion: get_text(m),
        meta: docx_meta(m)
      }
    end)
    |> Enum.reject(&blank_change?/1)
  end

  defp to_deletion_changes(deletions) do
    deletions
    |> Enum.map(fn m ->
      %Change{
        type: :deletion,
        deletion: get_text(m),
        meta: docx_meta(m)
      }
    end)
    |> Enum.reject(&blank_change?/1)
  end

  defp get_text(m), do: Map.get(m, :text) || Map.get(m, "text")

  defp docx_meta(m) do
    %{
      "source" => "docx",
      "id" => Map.get(m, :id) || Map.get(m, "id"),
      "author" => Map.get(m, :author) || Map.get(m, "author"),
      "date" => Map.get(m, :date) || Map.get(m, "date")
    }
  end

  defp blank_change?(%Change{type: :insertion, insertion: text}), do: blank_text?(text)
  defp blank_change?(%Change{type: :deletion, deletion: text}), do: blank_text?(text)
  defp blank_change?(_), do: true

  defp blank_text?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank_text?(_), do: true

  defp parse_changes(xml_content) do
    import SweetXml

    namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    insertions =
      xpath(
        xml_content,
        ~x"//w:ins"l
        |> add_namespace("w", namespace),
        id: ~x"./@w:id"s,
        author: ~x"./@w:author"s,
        date: ~x"./@w:date"s,
        text: ~x".//w:t/text()"sl |> add_namespace("w", namespace)
      )
      |> Enum.map(&normalize_change/1)
      |> Enum.reject(&is_nil/1)

    deletions =
      xpath(
        xml_content,
        ~x"//w:del"l
        |> add_namespace("w", namespace),
        id: ~x"./@w:id"s,
        author: ~x"./@w:author"s,
        date: ~x"./@w:date"s,
        text: ~x".//w:delText/text()"sl |> add_namespace("w", namespace)
      )
      |> Enum.map(&normalize_change/1)
      |> Enum.reject(&is_nil/1)

    %{deletions: deletions, insertions: insertions}
  rescue
    e ->
      Logger.warning("Error parsing DOCX track changes XML: #{Exception.message(e)}")
      %{deletions: [], insertions: []}
  end

  defp normalize_change(change) do
    text =
      change.text
      |> Enum.map_join("", &to_string/1)
      |> String.trim()

    if text != "" do
      %{
        author: change.author,
        date: change.date,
        id: change.id,
        text: text
      }
    end
  end

  defp clean_entries(entries, parts_set) do
    Enum.reduce_while(entries, {:ok, []}, fn {filename, content}, {:ok, acc} ->
      clean_entry(filename, content, parts_set, acc)
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      other -> other
    end
  end

  defp clean_entry(filename, content, parts_set, acc) do
    entry_name = to_string(filename)

    if MapSet.member?(parts_set, entry_name) do
      case Cleaner.accept_tracked_changes_xml(content) do
        {:ok, cleaned_xml} -> {:cont, {:ok, [{filename, cleaned_xml} | acc]}}
        {:error, reason} -> {:halt, {:error, {:xml_clean_error, entry_name, reason}}}
      end
    else
      {:cont, {:ok, [{filename, content} | acc]}}
    end
  end

  defp clean_entries_with_warnings(entries, parts_set) do
    Enum.reduce_while(entries, {:ok, [], []}, fn {filename, content}, {:ok, acc, warnings} ->
      entry_name = to_string(filename)

      if MapSet.member?(parts_set, entry_name) do
        case Cleaner.accept_tracked_changes_xml_with_warnings(content) do
          {:ok, cleaned_xml, file_warnings} ->
            file_warnings = Enum.map(file_warnings, &Map.put(&1, :part, entry_name))
            {:cont, {:ok, [{filename, cleaned_xml} | acc], file_warnings ++ warnings}}

          {:error, reason} ->
            {:halt, {:error, {:xml_clean_error, entry_name, reason}}}
        end
      else
        {:cont, {:ok, [{filename, content} | acc], warnings}}
      end
    end)
    |> case do
      {:ok, acc, warnings} -> {:ok, Enum.reverse(acc), Enum.reverse(warnings)}
      other -> other
    end
  end
end
