defmodule Redlines.PDF do
  @moduledoc """
  PDF adapter using the `pdf_redlines` package (precompiled Rust/MuPDF NIF).
  """

  alias Redlines.Change

  @doc """
  Extract redlines from a PDF file path.
  """
  @spec extract_redlines(Path.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def extract_redlines(pdf_path, opts \\ []) when is_binary(pdf_path) do
    case PDFRedlines.extract_redlines(pdf_path, opts) do
      {:ok, %PDFRedlines.Result{redlines: redlines}} -> {:ok, redlines}
      {:error, _} = error -> error
    end
  end

  @doc """
  Convert `pdf_redlines` entries into normalized changes.
  """
  @spec to_changes(list()) :: [Change.t()]
  def to_changes(redlines) when is_list(redlines) do
    redlines
    |> Enum.map(&to_change/1)
    |> Enum.reject(&is_nil/1)
  end

  def to_changes(_), do: []

  defp to_change(%{type: type} = redline) when type in [:deletion, :insertion, :paired] do
    %Change{
      type: type,
      deletion: Map.get(redline, :deletion) || Map.get(redline, "deletion"),
      insertion: Map.get(redline, :insertion) || Map.get(redline, "insertion"),
      location: Map.get(redline, :location) || Map.get(redline, "location"),
      meta: %{"source" => "pdf"}
    }
  end

  defp to_change(_), do: nil
end
