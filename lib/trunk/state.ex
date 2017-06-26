defmodule Trunk.State do
  @moduledoc """
  This module defines a `Trunk.State` struct and provides some helper functions for working with that state.
  """

  alias Trunk.VersionState

  defstruct module: nil,
            opts: [],
            filename: nil,
            rootname: nil,
            extname: nil,
            path: nil,
            versions: %{},
            async: true,
            version_timeout: 5_000,
            scope: %{},
            storage: nil,
            storage_opts: [],
            errors: nil,
            assigns: %{}
  @type t :: %__MODULE__{module: atom, opts: Keyword.t, filename: String.t, rootname: String.t, extname: String.t, path: String.t, versions: list(atom) | Keyword.t, async: boolean, version_timeout: integer, scope: map | struct, storage: atom, storage_opts: Keyword.t, errors: Keyword.t, assigns: map}

  def init(%{} = info, scope, opts) do
    filename = info[:filename]
    module = info[:module]
    path = info[:path]

    %__MODULE__{
      module: module,
      path: path,
      opts: opts,
      filename: filename,
      extname: Path.extname(filename),
      rootname: Path.rootname(filename),
      versions: opts |> Keyword.fetch!(:versions) |> Enum.map(&({&1, %VersionState{}})) |> Map.new,
      version_timeout: Keyword.fetch!(opts, :version_timeout),
      async: Keyword.fetch!(opts, :async),
      storage: Keyword.fetch!(opts, :storage),
      storage_opts: Keyword.fetch!(opts, :storage_opts),
      scope: scope,
    }
  end

  @doc ~S"""
  Puts an error into the error map.

  ## Example:
  ```
  iex> state.errors
  nil
  iex> state = put_error(state, :thumb, :transform, "Error with convert blah blah")
  iex> state.errors
  %{thumb: [transform: "Error with convert blah blah"]}
  ```
  """
  def put_error(%__MODULE__{errors: errors} = state, version, stage, error),
    do: %{state | errors: Map.update(errors || %{}, version, [{stage, error}], &([{stage, error} | &1]))}

  @doc ~S"""
  Assigns a value to a key on the state.

  ## Example:
  ```
  iex> state.assigns[:hello]
  nil
  iex> state = assign(state, :hello, :world)
  iex> state.assigns[:hello]
  :world
  ```
  """
  @spec assign(state :: Trunk.State.t, key :: any, value :: any) :: map
  def assign(%{assigns: assigns} = state, key, value),
    do: %{state | assigns: Map.put(assigns, key, value)}
end
