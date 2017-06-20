defmodule Trunk.State do
  defstruct ~w(module opts filename rootname extname path versions async version_timeout scope storage storage_opts errors assigns)a
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
      versions: opts |> Keyword.fetch!(:versions) |> Enum.map(&({&1, %{}})) |> Map.new,
      version_timeout: Keyword.fetch!(opts, :version_timeout),
      async: Keyword.fetch!(opts, :async),
      storage: Keyword.fetch!(opts, :storage),
      storage_opts: Keyword.fetch!(opts, :storage_opts),
      scope: scope,
      errors: nil,
    }
  end

  def put_error(%__MODULE__{errors: errors} = state, version, stage, error) do
    errors = Map.put(errors || %{}, version, {stage, error})
    %{state | errors: errors}
  end
end
