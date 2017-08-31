defmodule Trunk.Processor do
  @moduledoc false

  alias Trunk.State

  def store(%{versions: versions, async: true} = state),
    do: store_async(versions, state)
  def store(%{versions: versions, async: false} = state),
    do: store_sync(versions, state)

  defp store_async(versions, state) do
    process_async(versions, state, fn(version, map, state) ->
      with {:ok, map} <- get_version_transform(map, version, state),
           {:ok, map} <- transform_version(map, version, update_state(state, version, map)),
           {:ok, map} <- postprocess_version(map, version, update_state(state, version, map)),
           {:ok, map} <- get_version_storage_dir(map, version, update_state(state, version, map)),
           {:ok, map} <- get_version_filename(map, version, update_state(state, version, map)),
           {:ok, map} <- get_version_storage_opts(map, version, update_state(state, version, map)) do
        save_version(map, version, update_state(state, version, map))
      end
    end)
  end

  def store_sync(versions, %{versions: state_versions} = state) do
    with {:ok, versions, state} <- map_versions(versions, state, &get_version_transform/3),
         {:ok, versions, state} <- map_versions(versions, state, &transform_version/3),
         {:ok, versions, state} <- map_versions(versions, state, &postprocess_version/3),
         {:ok, versions, state} <- map_versions(versions, state, &get_version_storage_dir/3),
         {:ok, versions, state} <- map_versions(versions, state, &get_version_filename/3),
         {:ok, versions, state} <- map_versions(versions, state, &get_version_storage_opts/3),
         {:ok, versions, state} <- map_versions(versions, state, &save_version/3) do
      {:ok, %{state | versions: Map.merge(state_versions, Map.new(versions))}}
    end
  end

  def retrieve(%{versions: versions, storage: storage, storage_opts: storage_opts} = state, version) do
    map = versions[version]
    with {:ok, map} <- get_version_storage_dir(map, version, state),
         {:ok, %{filename: filename, storage_dir: storage_dir}} <- get_version_filename(map, version, state),
         {:ok, temp_path} <- Briefly.create(extname: Path.extname(filename)),
           :ok <- storage.retrieve(storage_dir, filename, temp_path, storage_opts) do
      {:ok, temp_path}
    end
  end

  def delete(%{versions: versions, async: true} = state) do
    process_async(versions, state, fn(version, map, state) ->
      with {:ok, map} <- get_version_storage_dir(map, version, update_state(state, version, map)),
      {:ok, map} <- get_version_filename(map, version, update_state(state, version, map)) do
        delete_version(map, version, update_state(state, version, map))
      end
    end)
  end
  def delete(%{versions: versions, async: false} = state) do
    state_versions = versions
    with {:ok, versions, state} <- map_versions(versions, state, &get_version_storage_dir/3),
         {:ok, versions, state} <- map_versions(versions, state, &get_version_filename/3),
         {:ok, versions, state} <- map_versions(versions, state, &delete_version/3) do
      {:ok, %{state | versions: Map.merge(state_versions, Map.new(versions))}}
    end
  end

  def process_async(versions, %{version_timeout: version_timeout} = state, func) do
    tasks =
      versions
      |> Enum.map(fn({version, map}) ->
        task = Task.async(fn -> func.(version, map, state) end)
        {version, task}
      end)

    task_list = Enum.map(tasks, fn({_version, task}) -> task end)

    task_list
    |> Task.yield_many(version_timeout)
    |> Enum.map(fn({task, result}) ->
      {task, result || Task.shutdown(task, :brutal_kill)}
    end)
    |> Enum.map(fn
      {task, nil} ->
        {find_task_version(tasks, task), {:error, :timeout}}
      {task, {:ok, response}} ->
        {find_task_version(tasks, task), response}
      {task, other} ->
        {find_task_version(tasks, task), other}
    end)
    |> Enum.reduce(state, fn
      {version, {:ok, map}}, %{versions: versions} = state ->
        versions = Map.put(versions, version, map)
        %{state | versions: versions}
      {version, {:error, error}}, state ->
        State.put_error(state, version, :processing, error)
      {version, {:error, stage, error}}, state ->
        State.put_error(state, version, stage, error)
    end)
    |> ok
  end

  defp find_task_version([], _task), do: nil
  defp find_task_version([{version, task} | _tail], task), do: version
  defp find_task_version([_head | tail], task),
    do: find_task_version(tail, task)

  defp update_state(%{versions: versions} = state, version, version_map),
    do: %{state | versions: Map.put(versions, version, version_map)}

  defp map_versions(versions, state, func) do
    {versions, state} =
      versions
      |> Enum.map_reduce(state, fn({version, map}, state) ->
        case func.(map, version, state) do
          {:ok, version_map} ->
            {{version, version_map}, state}
          {:error, stage, reason} ->
            {{version, map}, State.put_error(state, version, stage, reason)}
        end
      end)
    ok(versions, %{state | versions: Map.new(versions)})
  end

  def generate_url(%{versions: versions, storage: storage, storage_opts: storage_opts} = state, version) do
    map = versions[version]
    %{filename: filename, storage_dir: storage_dir} =
      with {:ok, map} = get_version_storage_dir(map, version, state),
           {:ok, map} = get_version_filename(map, version, state) do
        map
      end

    storage.build_uri(storage_dir, filename, storage_opts)
  end

  defp get_version_transform(version_state, version, %{module: module} = state),
    do: {:ok, Map.put(version_state, :transform, module.transform(state, version))}

  @doc false
  def transform_version(%{transform: nil} = version_state, _version, _state), do: ok(version_state)
  def transform_version(%{transform: transform} = version_state, _version, state) do
    case perform_transform(transform, state) do
      {:ok, temp_path} ->
        version_state
        |> Map.put(:temp_path, temp_path)
        |> ok
      {:error, error} ->
        {:error, :transform, error}
    end
  end

  defp postprocess_version(version_state, version, %{module: module} = state),
    do: module.postprocess(version_state, version, state)

  defp create_temp_path(%{}, {_, _, extname}),
    do: Briefly.create(extname: ".#{extname}")
  defp create_temp_path(%{extname: extname}, _),
    do: Briefly.create(extname: extname)

  defp perform_transform(transform, %{path: path}) when is_function(transform),
    do: transform.(path)
  defp perform_transform(transform, %{path: path} = state) do
    {:ok, temp_path} = create_temp_path(state, transform)
    perform_transform(transform, path, temp_path)
  end
  defp perform_transform({command, arguments, _ext}, source, destination),
    do: perform_transform(command, arguments, source, destination)
  defp perform_transform({command, arguments}, source, destination),
    do: perform_transform(command, arguments, source, destination)
  defp perform_transform(command, arguments, source, destination) do
    args = prepare_transform_arguments(source, destination, arguments)
    case System.cmd(to_string(command), args, stderr_to_stdout: true) do
      {_result, 0} -> {:ok, destination}
      {result, _} -> {:error, result}
    end
  end

  defp prepare_transform_arguments(source, destination, arguments) when is_function(arguments),
    do: arguments.(source, destination)
  defp prepare_transform_arguments(source, destination, [_ | _] = arguments),
    do: [source | arguments] ++ [destination]
  defp prepare_transform_arguments(source, destination, arguments),
    do: prepare_transform_arguments(source, destination, String.split(arguments, " "))

  defp get_version_storage_dir(version_state, version, %{module: module} = state),
    do: {:ok, %{version_state | storage_dir: module.storage_dir(state, version)}}

  defp get_version_storage_opts(version_state, version, %{module: module} = state),
    do: {:ok, %{version_state | storage_opts: module.storage_opts(state, version)}}

  defp get_version_filename(version_state, version, %{module: module} = state),
    do: {:ok, %{version_state | filename: module.filename(state, version)}}

  defp save_version(%{filename: filename, storage_dir: storage_dir, storage_opts: version_storage_opts, temp_path: temp_path} = version_state, _version, %{path: path, storage: storage, storage_opts: storage_opts}) do
    storage_opts = Keyword.merge(storage_opts, version_storage_opts)
    :ok = save_files(temp_path || path, filename, storage, storage_dir, storage_opts)
    {:ok, version_state}
  end

  defp save_files([], _filename, _storage, _storage_dir, _storate_opts), do: :ok
  defp save_files([_ | _] = paths, filename, storage, storage_dir, storage_opts) do
    paths
    |> Enum.zip(0..length(paths))
    |> Enum.each(fn({path, i}) ->
      :ok = save_files(path, multi_filename(filename, i), storage, storage_dir, storage_opts)
    end)
    :ok
  end
  defp save_files(path, filename, storage, storage_dir, storage_opts),
    do: storage.save(storage_dir, filename, path, storage_opts)

  defp multi_filename(filename, 0), do: filename
  defp multi_filename(filename, number) do
    rootname = Path.rootname(filename)
    extname = Path.extname(filename)
    "#{rootname}-#{number}#{extname}"
  end

  defp delete_version(%{filename: filename, storage_dir: storage_dir} = version_state, _version, %{storage: storage, storage_opts: storage_opts}) do
    :ok = storage.delete(storage_dir, filename, storage_opts)

    {:ok, version_state}
  end

  defp ok(%State{errors: nil} = state), do: {:ok, state}
  defp ok(%State{} = state), do: {:error, state}
  defp ok(other), do: {:ok, other}

  defp ok(versions, %State{errors: nil} = state), do: {:ok, versions, state}
  defp ok(_versions, %State{} = state), do: {:error, state}
end
