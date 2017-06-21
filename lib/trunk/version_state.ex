defmodule Trunk.VersionState do
  @moduledoc """
  This module defines a `Trunk.VersionState` struct and provides some helper functions for working with that state.
  """

  defstruct temp_path: nil, opts: [], transform: nil, transform_result: nil, assigns: %{}
  @type t :: %__MODULE__{temp_path: String.t, opts: Keyword.t, transform: any, transform_result: any, assigns: map}

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
