defmodule Trunk.VersionState do
  @moduledoc """
  This module defines a `Trunk.VersionState` struct and provides some helper functions for working with that state.

  Most of these fields are used internally during processing.

  ## Fields
  The following fields are available in the version state object. Some values are filled in during processing.
  - `temp_path` - The path to the temporary file created for transformation. If the version doesn't undergo transformation, no temporary path will be available.
  - `transform` - The transform instruction returned from `c:Trunk.transform/2`
  - `storage_dir` - The storage directory returned from `c:Trunk.storage_dir/2`
  - `filename` - The filename returned from `c:Trunk.filename/2`
  - `storage_opts` - The additional storage options returned from `c:Trunk.storage_opts/2`
  - `assigns` - shared user data as a map (Same as assigns in  `Plug.Conn`)

  ## Usage
  This information is made available during `c:Trunk.postprocess/3` which is called once the transformation is complete but before the storage callbacks are called. At this point you can work with the transformed version file and assign data that can be used later when determining the storage directory, filename and storage options.
  """

  defstruct temp_path: nil,
            transform: nil,
            assigns: %{},
            storage_dir: nil,
            filename: nil,
            storage_opts: []
  @type t :: %__MODULE__{temp_path: String.t, transform: any, assigns: map, storage_dir: String.t, filename: String.t, storage_opts: Keyword.t}

  @doc ~S"""
  Assigns a value to a key on the state.

  ## Example:
  ```
  iex> version_state.assigns[:hello]
  nil
  iex> version_state = assign(version_state, :hello, :world)
  iex> version_state.assigns[:hello]
  :world
  ```
  """
  @spec assign(state :: Trunk.VersionState.t, key :: any, value :: any) :: map
  def assign(%{assigns: assigns} = version_state, key, value),
    do: %{version_state | assigns: Map.put(assigns, key, value)}
end
