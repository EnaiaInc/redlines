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
      {:ok, %{redlines: redlines}} when is_list(redlines) -> {:ok, redlines}
      {:ok, %_{redlines: redlines}} when is_list(redlines) -> {:ok, redlines}
      {:ok, other} -> {:error, {:unexpected_pdf_redlines_result, other}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Fast redline presence check for PDFs (early-exit).
  """
  @spec has_redlines?(Path.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def has_redlines?(pdf_path, opts \\ []) when is_binary(pdf_path) do
    PDFRedlines.has_redlines?(pdf_path, opts)
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
