defmodule Trunk.State do
  @moduledoc """
  This module defines a `Trunk.State` struct and provides some helper functions for working with that state.
  """

  alias Trunk.VersionState

  defstruct module: nil,
            opts: [],
            filename: nil,
            rootname: nil,
            lower_extname: nil,
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
  @type opts :: Keyword.t
  @type t :: %__MODULE__{module: atom, opts: opts, filename: String.t, rootname: String.t, extname: String.t, lower_extname: String.t, path: String.t, versions: list(atom) | Keyword.t, async: boolean, version_timeout: integer, scope: map | struct, storage: atom, storage_opts: Keyword.t, errors: Keyword.t, assigns: map}

  def init(%{} = info, scope, opts) do
    filename = info[:filename]
    module = info[:module]
    path = info[:path]
    extname = Path.extname(filename)

    %__MODULE__{
      module: module,
      path: path,
      opts: opts,
      filename: filename,
      extname: extname,
      lower_extname: String.downcase(extname),
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

  def get_version_assign(%{versions: versions}, version, assign) do
    case versions[version] do
      %{assigns: %{^assign => value}} -> value
      _ -> nil
    end
  end

  @doc ~S"""
  Extracts the data needed from the state in order to reconstruct the file paths in future.

  Options:
  - `:as` - How to save the state.
    - `:string` - Default, will just save the file name. An error will be raised if there are any assigns unless `:ignore_assigns` is set to tru
    - `:map` - will save a map with keys `:filename`, `:assigns`, and `:version_assigns`
    - `:json` - will save a map encoded as JSON (Requires Poison library to be included in deps)
  - `:ignore_assigns` boolean, default false. Use this to save as string and ignore any assigns (Make sure you’re not using assigns for `c:Trunk.storage_dir/2` or `c:Trunk.filename/2`)
  - `:assigns` - a list of keys to save from the assigns hashes

  ## Example:
  ```
  iex> Trunk.State.save(%Trunk.State{filename: "photo.jpg"})
  "photo.jpg"
  iex> Trunk.State.save(%Trunk.State{filename: "photo.jpg", assigns: %{hash: "abcdef"}}, as: :map)
  %{filename: "photo.jpg", assigns: %{hash: "abcdef"}}
  iex> Trunk.State.save(%Trunk.State{filename: "photo.jpg", assigns: %{hash: "abcdef", file_size: 12345}}, as: :map, assigns: [:hash])
  %{filename: "photo.jpg", assigns: %{hash: "abcdef"}}
  iex> Trunk.State.save(%Trunk.State{filename: "photo.jpg", assigns: %{hash: "abcdef"}}, as: :json)
  "{\"filename\": \"photo.jpg\", \"assigns\": {\"hash\": \"abcdef\"}}"
  ```
  """
  @type assign_keys :: [atom]
  @type save_opts :: [assigns: :all | assign_keys]
  @spec save(Trunk.State.t) :: String.t
  @spec save(Trunk.State.t, [{:as, :string} | save_opts]) :: String.t
  @spec save(Trunk.State.t, [{:as, :json} | save_opts]) :: String.t
  @spec save(Trunk.State.t, [{:as, :map} | save_opts]) :: map
  def save(state, opts \\ []) do
    save_as = Keyword.get(opts, :as, :string)
    save_as(state, save_as, opts)
  end

  defp save_as(%{filename: filename} = state, :string, opts) do
    unless Keyword.get(opts, :ignore_assigns, false), do: assert_no_assigns(state)
    filename
  end
  if Code.ensure_loaded?(Poison),
    do: defp save_as(state, :json, opts), do: state |> save_as(:map, opts) |> Poison.encode!
  defp save_as(%{filename: filename, assigns: assigns, versions: versions}, :map, opts),
    do: %{filename: filename,
          assigns: save_assigns(assigns, Keyword.get(opts, :assigns, :all)),
          version_assigns: versions |> Enum.map(fn({version, %{assigns: assigns}}) ->
            {version, save_assigns(assigns, Keyword.get(opts, :assigns, :all))}
          end) |> Map.new}

  defp assert_no_assigns(%{assigns: assigns}) when assigns != %{},
    do: raise ArgumentError, message: "Cannot save state as string with non-empty assigns hash"
  defp assert_no_assigns(%{versions: versions}),
    do: Enum.each(versions, fn({_version, state}) -> assert_no_assigns(state) end)
  defp assert_no_assigns(%{}), do: nil

  defp save_assigns(map, :all), do: map
  defp save_assigns(map, keys), do: Map.take(map, keys)

  @doc ~S"""
  Restore a saved state from a filename, JSON, or a map

  ## Example:
  ```
  iex> Trunk.State.restore("photo.jpg")
  %Trunk.State{filename: "photo.jpg"}
  iex> Trunk.State.restore(%{filename: "photo.jpg", assigns: %{hash: "abcdef"}}
  %Trunk.State{filename: "photo.jpg", assigns: %{hash: "abcdef"}}
  iex> Trunk.State.restore(%{"filename" => "photo.jpg", "assigns" => %{"hash" => "abcdef"}}
  %Trunk.State{filename: "photo.jpg", assigns: %{hash: "abcdef"}}
  iex> Trunk.State.restore("{\"filename\": \"photo.jpg\", \"assigns\": {\"hash\": \"abcdef\"}}")
  %Trunk.State{filename: "photo.jpg", assigns: %{hash: "abcdef"}}
  ```
  """
  @type file_info :: String.t | map
  @spec restore(file_info) :: Trunk.State.t
  def restore(file_info)
  if Code.ensure_loaded?(Poison) do
    def restore(<<"{", _rest::binary>> = json) do
      {:ok, map} = Poison.decode(json)
      map
      |> keys_to_atom
      |> restore

    end
  end
  def restore(<<filename::binary>>),
    do: %__MODULE__{filename: filename}
  def restore(%{version_assigns: version_assigns} = info) do
    state = struct(__MODULE__, info)
    versions =
      version_assigns
      |> Enum.map(fn({version, assigns}) ->
        {version, %VersionState{assigns: assigns}}
      end)
      |> Map.new
    %{state | versions: versions}
  end
  def restore(%{} = map), do: map |> keys_to_atom |> restore

  defp keys_to_atom(%{} = map) do
    map
    |> Enum.map(fn({key, value}) ->
      try do
        {String.to_existing_atom(key), keys_to_atom(value)}
      rescue
        ArgumentError ->
          {key, keys_to_atom(value)}
      end
    end)
    |> Map.new
  end
  defp keys_to_atom(arg), do: arg
end
