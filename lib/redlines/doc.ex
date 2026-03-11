defmodule Redlines.DOC do
  @moduledoc """
  Legacy `.doc` adapter using the optional `doc_redlines` package.
  """

  alias Redlines.Change

  @doc """
  Extract redlines from a legacy `.doc` file path.

  Returns `{:error, :doc_redlines_not_available}` when the `DocRedlines`
  module is not loaded in the current runtime.
  """
  @spec extract_redlines(Path.t()) :: {:ok, list()} | {:error, term()}
  def extract_redlines(path) when is_binary(path) do
    with :ok <- ensure_doc_redlines_loaded(),
         {:ok, %{redlines: redlines}} <- apply(DocRedlines, :extract_redlines, [path]) do
      {:ok, redlines}
    else
      {:error, _reason} = error -> error
      :error -> {:error, :doc_redlines_not_available}
      false -> {:error, :doc_redlines_not_available}
      other -> {:error, {:unexpected_doc_redlines_result, other}}
    end
  end

  @doc """
  Convert `doc_redlines` entries into normalized changes.
  """
  @spec to_changes(list()) :: [Change.t()]
  def to_changes(redlines) when is_list(redlines) do
    redlines
    |> Enum.map(&to_change/1)
    |> Enum.reject(&is_nil/1)
  end

  def to_changes(_), do: []

  defp ensure_doc_redlines_loaded do
    if Code.ensure_loaded?(DocRedlines) and function_exported?(DocRedlines, :extract_redlines, 1) do
      :ok
    else
      :error
    end
  end

  defp to_change(%{type: :insertion} = redline) do
    %Change{
      type: :insertion,
      insertion: read_text(redline),
      location: Map.get(redline, :location) || Map.get(redline, "location"),
      meta: build_meta(redline)
    }
  end

  defp to_change(%{type: :deletion} = redline) do
    %Change{
      type: :deletion,
      deletion: read_text(redline),
      location: Map.get(redline, :location) || Map.get(redline, "location"),
      meta: build_meta(redline)
    }
  end

  defp to_change(%{type: :paired} = redline) do
    %Change{
      type: :paired,
      deletion: Map.get(redline, :deletion) || Map.get(redline, "deletion"),
      insertion: Map.get(redline, :insertion) || Map.get(redline, "insertion"),
      location: Map.get(redline, :location) || Map.get(redline, "location"),
      meta: build_meta(redline)
    }
  end

  defp to_change(_), do: nil

  defp build_meta(redline) do
    %{
      "source" => "doc",
      "author" => read_field(redline, :author),
      "timestamp" => normalize_timestamp(read_field(redline, :timestamp)),
      "paragraph_index" => read_field(redline, :paragraph_index),
      "char_offset" => read_field(redline, :char_offset),
      "context" => read_field(redline, :context)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp read_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp read_text(map) do
    Map.get(map, :text) || Map.get(map, "text")
  end

  defp normalize_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_timestamp(value), do: value
end
