defmodule Trunk.Storage do
  @moduledoc """
  This is a behaviour that can be implemented by any storage module to make sure it supports all required functions.
  """

  @type opts :: Keyword.t

  @doc ~S"""
  Save the `source_file` to the storage system on path `Path.join(directory, filename)`

  - `directory` - The directory
  - `filename` - The name of the file
  - `source_path` - The full path to the file to be stored. This is a path to the uploaded file or a temporary file that has undergone transformation
  - `opts` - The options for the storage system, set in Trunk option `:storage_opts`

  ## Example:
  The file should be saved to <storage system>/my-bucket/path/to/file.ext
  ```
  MyStorage.save("path/to/", "file.ext", "/tmp/uploaded_file.ext", some: :opt)
  """
  @callback save(directory :: String.t, filenae :: String.t, source_path :: String.t, opts) :: :ok | {:error, any}

  @doc ~S"""
  Deletes the version file from the storage system at path `Path.join(directory, filename)`

  - `directory` - The directory
  - `filename` - The name of the file
  - `opts` - The options for the storage system, set in Trunk option `:storage_opts`

  ## Example:
  The file should be removed from <storage system>/my-bucket/path/to/file.ext
  ```
  MyStorage.delete("path/to/", "file.ext", some: :opt)
  """
  @callback delete(directory :: String.t, filenae :: String.t, opts) :: :ok | {:error, any}

  @doc ~S"""
  Generates a URL to the S3 object

  - `directory` - The directory
  - `filename` - The name of the file
  - `opts` - The options for the storage system, set in Trunk option `:storage_opts`

  ## Example:
  ```
  MyStorage.build_url("path/to", "file.ext", some: :opt)
  #=> "https://my-storage/my-bucket/path/to/file.ext"
  ```
  """
  @callback build_uri(directory :: String.t, filename :: String.t, opts) :: String.t
end
