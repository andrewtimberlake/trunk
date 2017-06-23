defmodule Trunk.Storage.Filesystem do
  @moduledoc """
  A `Trunk.Storage` implementation for the local file system.
  """

  @behaviour Trunk.Storage

  @doc ~S"""
  Saves the file to the file system.

  - `directory` - The relative directory within which to store the file
  - `filename` - The name of the file to be saved
  - `source_path` - The full path to the file to be stored. This is a path to the uploaded file or a temporary file that has undergone transformation
  - `opts` - The options for the storage system
    - `path:` (required) The base path within which to save files
    - `acl:` (optional) The file mode to store the file (accepts octal `0o644` or string `"0644"`). See `File.chmod/2` for more info.

  ## Example:
  The file will be saved to /opts/uploads/path/to/file.ext
  ```
  Trunk.Storage.Filesystem.save("path/to/", "file.ext", "/tmp/uploaded_file.ext", path: "/opt/uploads")
  """
  @spec save(String.t, String.t, String.t, keyword) :: :ok | {:error, :file.posix}
  def save(directory, filename, source_path, opts \\ []) do
    base_directory = Keyword.fetch!(opts, :path)
    save_path = Path.join(base_directory, directory)
    file_path = Path.join(save_path, filename)
    with :ok = File.mkdir_p(save_path) do
      result = File.cp(source_path, file_path)
      acl = parse_acl(Keyword.get(opts, :acl))
      if acl, do: File.chmod(file_path, acl), else: result
    end
  end

  defp parse_acl(nil), do: nil
  defp parse_acl(<<mode::binary>>) do
    {number, ""} = Integer.parse(mode, 8)
    number
  end
  defp parse_acl(number) when is_number(number), do: number

  @doc ~S"""
  Deletes the file from the file system.

  - `directory` - The relative directory within which to store the file
  - `filename` - The name of the file to be saved
  - `opts` - The options for the storage system
    - `path:` (required) The base path within which to save files

  ## Example:
  The file will be removed from /opts/uploads/path/to/file.ext
  ```
  Trunk.Storage.Filesystem.delete("path/to/", "file.ext", path: "/opt/uploads")
  """
  @spec delete(String.t, String.t, keyword) :: :ok | {:error, :file.posix}
  def delete(directory, filename, opts \\ []) do
    base_directory = Keyword.fetch!(opts, :path)
    file_path = base_directory |> Path.join(directory)
    case File.rm(Path.join(file_path, filename)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc ~S"""
  Generates a URL for the storage directory and file

  - `directory` - The relative directory where the file is saved
  - `filename` - The name of the file that was previous saved
  - `opts` - The options for the storage system
    - `base_url:` (optional) The base url to join the path to

  ## Example:
  ```
  Trunk.Storage.Filesystem.build_url("path/to", "file.ext")
  #=> "path/to/file.ext"
  Trunk.Storage.Filesystem.build_url("path/to", "file.ext", base_uri: "http://example.com")
  #=> "http://example.com/path/to/file.ext"
  Trunk.Storage.Filesystem.build_url("path/to", "file.ext", base_uri: "http://example.com/uploads/")
  #=> "http://example.com/uploads/path/to/file.ext"
  Trunk.Storage.Filesystem.build_url("path/to", "file.ext", base_uri: "/uploads/")
  #=> "/uploads/path/to/file.ext"
  ```
  """
  def build_uri(directory, filename, opts \\ []) do
    base_uri = Keyword.get(opts, :base_uri) || ""
    base_uri |> Path.join(directory) |> Path.join(filename)
  end
end
