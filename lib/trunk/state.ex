defmodule Trunk.State do
  @moduledoc """
  This module defines a `Trunk.State` struct and provides some helper functions for working with that state.

  ## Fields
  The following fields are available in the state object. Some values are filled in during processing.
  - `filename` - The base filename of the file being processed. (e.g. `"photo.jpg"`)
  - `rootname` - The root of the filen being processed. (e.g. `"photo"`)
  - `extname` - The file extension of the file being processed. (e.g. `".jpg"`)
  - `lower_extname` - The file extension of the file being processed forced to lower case (e.g. `"*.jpg"`, even if the file is `"PHOTO.JPG"`)
  - `path` - The full path to the file being processed. If the file was passed in as a binary, it is a path to the temporary file created with that binary.
  - `versions` - A map of the versions and their respective `Trunk.VersionState` (e.g. `%{original: %Trunk.VersionState{}, thumbnail: %Trunk.VersionState{}}`)
  - `scope` - A user struct/map passed in useful for determining storage locations and file naming.
  - `async` - A boolean indicator of whether processing will be done in parallel.
  - `version_timeout` - The timeout after which each processing process will be terminated. (Only applies with `async: true`)
  - `storage` - The module to use for storage processing. (e.g. `Trunk.Storage.Filesystem` or `Trunk.Storage.S3`)
  - `storage_opts` - A keyword list of options for the `storage` module
  - `errors` - a place to record errors encountered during processing. (`nli` if no errors, otherwise a map of errors)
  - `opts` - All the options merged together (see Options in `Trunk` module documentation).
  - `assigns` - shared user data as a map (Same as assigns in  `Plug.Conn`)
  """

  alias Trunk.VersionState

  defstruct module: nil,
            path: nil,
            filename: nil,
            rootname: nil,
            extname: nil,
            lower_extname: nil,
            versions: %{},
            scope: %{},
            async: true,
            version_timeout: 5_000,
            storage: nil,
            storage_opts: [],
            errors: nil,
            opts: [],
            assigns: %{}
  @type opts :: Keyword.t
  @type t :: %__MODULE__{module: atom, opts: opts, filename: String.t, rootname: String.t, extname: String.t, lower_extname: String.t, path: String.t, versions: map, async: boolean, version_timeout: integer, scope: map | struct, storage: atom, storage_opts: Keyword.t, errors: Keyword.t, assigns: map}

  def init(%{} = info, scope, opts) do
    state = restore(info, opts)
    rootname = Path.rootname(state.filename)
    extname = Path.extname(state.filename)
    %{state |
      extname: extname,
      lower_extname: String.downcase(extname),
      rootname: rootname,
      version_timeout: Keyword.fetch!(opts, :version_timeout),
      async: Keyword.fetch!(opts, :async),
      storage: Keyword.fetch!(opts, :storage),
      storage_opts: Keyword.fetch!(opts, :storage_opts),
      scope: scope,
      opts: opts,
    }
  end

  @doc ~S"""
  Puts an error into the error map.

  ## Example:
  ```
  iex> state.errors
  nil
  iex> state = Trunk.State.put_error(state, :thumb, :transform, "Error with convert blah blah")
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
  iex> state = Trunk.State.assign(state, :hello, :world)
  iex> state.assigns[:hello]
  :world
  ```
  """
  @spec assign(state :: Trunk.State.t, key :: any, value :: any) :: map
  def assign(%{assigns: assigns} = state, key, value),
    do: %{state | assigns: Map.put(assigns, key, value)}

  @doc ~S"""
  Retrieves an assign value for a specific version.

  ## Example:
  ```
  iex> state = %Trunk.State{versions: %{thumbnail: %Trunk.VersionState{assigns: %{hello: :world}}}}
  iex> %Trunk.State.get_version_assign(state, :thumbnail, :hello)
  :world
  iex> %Trunk.State.get_version_assign(state, :thumbnail, :unknown)
  nil
  ```
  """
  @type version :: atom
  @spec get_version_assign(state :: Trunk.State.t, version, assign :: atom) :: any | nil
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
  defp save_as(state, :json, opts), do: state |> save_as(:map, opts) |> Poison.encode!
  defp save_as(%{filename: filename, assigns: assigns, versions: versions}, :map, opts) do
    assigns_to_save = Keyword.get(opts, :assigns, :all)
    %{filename: filename}
    |> save_assigns(assigns, assigns_to_save)
    |> save_version_assigns(versions, assigns_to_save)
  end

  defp assert_no_assigns(%{assigns: assigns}) when assigns != %{},
    do: raise ArgumentError, message: "Cannot save state as string with non-empty assigns hash"
  defp assert_no_assigns(%{versions: versions}),
    do: Enum.each(versions, fn({_version, state}) -> assert_no_assigns(state) end)
  defp assert_no_assigns(%{}), do: nil

  defp save_assigns(map, assigns, _keys) when assigns == %{}, do: map
  defp save_assigns(map, assigns, :all), do: Map.put(map, :assigns, assigns)
  defp save_assigns(map, assigns, keys), do: Map.put(map, :assigns, Map.take(assigns, keys))

  defp save_version_assigns(map, versions, keys) do
    version_assigns =
      versions
      |> Enum.map(fn
        {version, %{assigns: assigns}} when assigns == %{} ->
          {version, nil}
        {version, %{assigns: assigns}} ->
          {version, (if keys == :all, do: assigns, else: Map.take(assigns, keys))}
      end)
      |> Enum.filter(fn({_version, value}) -> value end)
      |> Map.new

    if Enum.empty?(version_assigns), do: map, else: Map.put(map, :version_assigns, version_assigns)
  end

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
  @spec restore(file_info, opts) :: Trunk.State.t
  def restore(file_info, opts \\ [])
  def restore(<<"{", _rest::binary>> = json, opts) do
    {:ok, map} = Poison.decode(json)
    map
    |> keys_to_atom
    |> restore(opts)
  end
  def restore(<<filename::binary>>, opts),
    do: restore(%{filename: filename}, opts)
  def restore(%{} = info, opts) do
    info = keys_to_atom(info)
    state = struct(__MODULE__, info)
    version_assigns = info[:version_assigns] || %{}
    versions =
      opts
      |> Keyword.fetch!(:versions)
      |> Enum.map(fn(version) ->
        assigns = version_assigns[version] || %{}
        {version, %VersionState{assigns: assigns}}
      end)
      |> Map.new

    %{state | versions: versions}
  end

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
