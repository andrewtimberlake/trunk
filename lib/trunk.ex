defmodule Trunk do
  defmodule State do
    defstruct ~w(module file opts filename extname rootname save_path versions async version_timeout scope)a

    def init(%{} = info, scope, opts) do
      filename = info[:filename]
      module = info[:module]
      file = info[:file]

      %State{
        module: module,
        file: file,
        opts: opts,
        filename: filename,
        extname: Path.extname(filename),
        rootname: Path.rootname(filename),
        save_path: Keyword.fetch!(opts, :path),
        versions: opts |> Keyword.fetch!(:versions) |> Enum.map(&({&1, %{}})) |> Map.new,
        version_timeout: Keyword.fetch!(opts, :version_timeout),
        async: Keyword.fetch!(opts, :async),
        scope: scope,
      }
    end
  end

  defmacro __using__(module_opts \\ []) do
    # IO.inspect(module_opts)

    quote location: :keep do
      def store(file, scope \\ nil, opts \\ [])
      def store(file, [_ | _] = opts, []),
        do: store(file, nil, opts)
      def store(file, scope, opts) do
        opts = Trunk.parse_options(unquote(module_opts), opts)
        filename = Path.basename(file)
        state = State.init(%{file: file, filename: filename, module: __MODULE__}, scope, opts)

        Trunk.process(state)
      end

      def url(info, scope \\ nil, version \\ :original, opts \\ [])

      def url(<<filename::binary>>, scope, version, opts),
        do: url(%{filename: filename}, scope, version, opts)

      def url(info, [_ | _] = opts, _, _),
        do: url(info, nil, :original, opts)
      def url(info, version, [_ | _] = opts, []) when is_atom(version),
        do: url(info, nil, version, opts)
      def url(info, state, [_ | _] = opts, []),
        do: url(info, state, :original, opts)

      def url(%{} = info, scope, version, opts) do
        opts = Trunk.parse_options(unquote(module_opts), opts)
        state = State.init(Map.merge(info, %{module: __MODULE__}), scope, opts)

        Trunk.generate_url(state, version)
      end

      def filename(%{filename: filename}, :original), do: filename
      def filename(%{rootname: rootname, extname: extname}, version),
        do: rootname <> "_" <> to_string(version) <> extname

      def storage_dir(state, version), do: ""

      def transform(state, version), do: nil

      defoverridable transform: 2, filename: 2, storage_dir: 2
    end
  end

  def process(%{versions: versions, version_timeout: version_timeout, async: true} = state) do
    versions =
      versions
      |> Enum.map(fn({version, map}) ->
        task = Task.async(fn ->
          map
          |> get_version_transform(version, state)
          |> transform_version(version, state)
          |> get_version_filename(version, state)
          |> get_version_storage_dir(version, state)
          |> save_version(version, state)
        end)
        {version, task}
      end)
      |> Enum.map(fn({version, task}) ->
        {version, Task.await(task, version_timeout)}
      end)
      |> Map.new

    {:ok, %{state | versions: versions}}
  end
  def process(%{async: false} = state) do
    with {:ok, state} <- get_version_transforms(state),
         {:ok, state} <- transform_versions(state),
         {:ok, state} <- get_version_storage_dirs(state),
         {:ok, state} <- get_version_filenames(state) do
      save_versions(state)
    end
  end

  def generate_url(%{save_path: save_path, versions: versions} = state, version) do
    %{filename: filename, storage_dir: storage_dir} =
      versions[version]
      |> get_version_storage_dir(version, state)
      |> get_version_filename(version, state)

    save_path |> Path.join(storage_dir) |> Path.join(filename)
  end

  defp get_version_transforms(state),
    do: {:ok, map_versions(state, &get_version_transform/3)}

  defp get_version_transform(version_state, version, %{module: module} = state),
    do: Map.put(version_state, :transform, module.transform(state, version))

  defp transform_versions(state),
    do: {:ok, map_versions(state, &transform_version/3)}

  defp transform_version(%{transform: nil} = version_state, _version, _state), do: version_state
  defp transform_version(%{transform: transform} = version_state, _version, %{file: file} = state) do
    {:ok, temp_file} = create_temp_file(state, transform)
    result = perform_transform(transform, file, temp_file)
      version_state
      |> Map.put(:transform_result, result)
      |> Map.put(:temp_file, temp_file)
  end

  defp create_temp_file(%{}, {_, _, extname}),
    do: Briefly.create(extname: ".#{extname}")
  defp create_temp_file(%{extname: extname}, _),
    do: Briefly.create(extname: extname)

  defp perform_transform({command, arguments, _extname}, source, destination),
    do: perform_transform({command, arguments}, source, destination)
  defp perform_transform({command, arguments}, source, destination) do
    args = [source | String.split(arguments, " ")] ++ [destination]

    case System.cmd(to_string(command), args, stderr_to_stdout: true) do
      {_result, 0} -> :ok
      {result, _} -> {:error, result}
    end
  end

  defp get_version_storage_dirs(state),
    do: {:ok, map_versions(state, &get_version_storage_dir/3)}

  defp get_version_storage_dir(version_state, version, %{module: module} = state),
    do: Map.put(version_state, :storage_dir, module.storage_dir(state, version))

  defp get_version_filenames(state),
    do: {:ok, map_versions(state, &get_version_filename/3)}

  defp get_version_filename(version_state, version, %{module: module} = state),
    do: Map.put(version_state, :filename, module.filename(state, version))

  defp save_versions(state),
    do: {:ok, map_versions(state, &save_version/3)}

  defp save_version(%{filename: filename, storage_dir: storage_dir} = version_state, _version, %{file: file, save_path: save_path}) do
    full_dir = save_path |> Path.join(storage_dir)
    :ok = File.mkdir_p(full_dir)
    :ok = File.open!(Path.join(full_dir, filename), [:write, :binary], fn(f) ->
      IO.binwrite(f, File.read!(version_state[:temp_file] || file))
    end)
    version_state
  end

  defp map_versions(%{versions: versions} = state, func) do
    %{state | versions: map_versions(versions, state, func)}
  end
  defp map_versions(versions, state, func) do
    versions
    |> Enum.map(fn({version, map}) -> {version, func.(map, version, state)} end)
  end

  def parse_options(module_opts, method_opts) do
    defaults = [
      versions: [:original],
      async: true,
      version_timeout: 5_000,
      acl: :private,
    ]

    defaults
    |> Keyword.merge(Application.get_all_env(:trunk))
    |> merge_otp_app_opts(module_opts)
    |> Keyword.merge(module_opts)
    |> Keyword.merge(method_opts)
    |> filter_options
  end

  defp merge_otp_app_opts(opts, module_opts) do
    otp_app = Keyword.get(module_opts, :otp_app, [])
    otp_opts = Application.get_env(otp_app, :trunk, [])
    Keyword.merge(opts, otp_opts)
  end

  defp filter_options(opts, acc \\ [])
  defp filter_options([], acc), do: acc
  defp filter_options([{:async, async} | tail], acc),
    do: filter_options(tail, [{:async, async} | acc])
  defp filter_options([{:path, path} | tail], acc),
    do: filter_options(tail, [{:path, path} | acc])
  defp filter_options([{:versions, versions} | tail], acc),
    do: filter_options(tail, [{:versions, versions} | acc])
  defp filter_options([{:version_timeout, version_timeout} | tail], acc),
    do: filter_options(tail, [{:version_timeout, version_timeout} | acc])
  defp filter_options([_head | tail], acc),
    do: filter_options(tail, acc)
end
