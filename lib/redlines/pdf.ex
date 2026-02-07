defmodule Redlines.PDF do
  @moduledoc """
  PDF adapter.

  This module integrates with the `pdf_redlines` package (Rust/MuPDF NIF) if it
  is available at runtime.
  """

  alias Redlines.Change

  @doc """
  Extract redlines from a PDF file path.

  Requires the `pdf_redlines` package to be present in the caller's dependency
  tree.
  """
  @spec extract_redlines(Path.t(), keyword() | map()) :: {:ok, list()} | {:error, term()}
  def extract_redlines(pdf_path, opts \\ []) when is_binary(pdf_path) do
    with {:ok, arity} <- ensure_pdf_redlines_loaded(:extract_redlines),
         {:ok, result} <- do_apply(PDFRedlines, :extract_redlines, arity, [pdf_path, opts]) do
      case result do
        %{redlines: redlines} when is_list(redlines) -> {:ok, redlines}
        %_{redlines: redlines} when is_list(redlines) -> {:ok, redlines}
        other -> {:error, {:unexpected_pdf_redlines_result, other}}
      end
    end
  end

  @doc """
  Fast redline presence check for PDFs (early-exit in `pdf_redlines`).
  """
  @spec has_redlines?(Path.t(), keyword() | map()) :: {:ok, boolean()} | {:error, term()}
  def has_redlines?(pdf_path, opts \\ []) when is_binary(pdf_path) do
    with {:ok, arity} <- ensure_pdf_redlines_loaded(:has_redlines?) do
      do_apply(PDFRedlines, :has_redlines?, arity, [pdf_path, opts])
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

  defp ensure_pdf_redlines_loaded(fun) when is_atom(fun) do
    cond do
      Code.ensure_loaded?(PDFRedlines) and function_exported?(PDFRedlines, fun, 2) ->
        {:ok, 2}

      Code.ensure_loaded?(PDFRedlines) and function_exported?(PDFRedlines, fun, 1) ->
        {:ok, 1}

      true ->
        {:error, :pdf_redlines_not_available}
    end
  end

  defp do_apply(mod, fun, 2, [path, opts]), do: apply(mod, fun, [path, opts])
  defp do_apply(mod, fun, 1, [path, _opts]), do: apply(mod, fun, [path])
end
