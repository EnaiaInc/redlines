defmodule Redlines.Result do
  @moduledoc """
  Extraction result.
  """

  alias Redlines.Change

  @enforce_keys [:changes, :source]
  defstruct changes: [], source: nil

  @type source :: :pdf | :docx

  @type t :: %__MODULE__{
          source: source(),
          changes: [Change.t()]
        }
end
