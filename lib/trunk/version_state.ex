defmodule Trunk.VersionState do
  defstruct temp_path: nil, opts: [], transform: nil, transform_result: nil, assigns: %{}
  @type t :: %__MODULE__{temp_path: String.t, opts: Keyword.t, transform: any, transform_result: any, assigns: map}
end
