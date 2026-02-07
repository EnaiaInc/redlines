defmodule Redlines.Change do
  @moduledoc """
  A single tracked-change entry, normalized across sources.
  """

  @enforce_keys [:type]
  defstruct type: nil,
            deletion: nil,
            insertion: nil,
            location: nil,
            meta: %{}

  @type type :: :deletion | :insertion | :paired

  @type t :: %__MODULE__{
          type: type(),
          deletion: String.t() | nil,
          insertion: String.t() | nil,
          location: String.t() | nil,
          meta: map()
        }
end
