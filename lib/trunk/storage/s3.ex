if match?({:module, _}, Code.ensure_compiled(ExAws.S3)) do
  defmodule Trunk.Storage.S3 do
    @moduledoc """
    A `Trunk.Storage` implementation for Amazon’s S3 service.
    """

    @behaviour Trunk.Storage

    @doc ~S"""
    Saves the file to Amazon S3.

    - `directory` - The directory (will be combined with the `filename` to form the S3 object key).
    - `filename` - The name of the file (will be combined with the `directory` to form the S3 object key).
    - `source_path` - The full path to the file to be stored. This is a path to the uploaded file or a temporary file that has undergone transformation
    - `opts` - The options for the storage system
      - `bucket:` (required) The S3 bucket in which to store the object
      - `ex_aws:` (optional) override options for `ex_aws`
      - All other options are passed through to S3 put object which means you can pass in anything accepted by `t:ExAws.S3.put_object_opts/0` including but not limited to `:acl`, `:meta`, `:content_type`, and `:content_disposition`

    ## Example:
    The file will be saved to s3.amazonaws.com/my-bucket/path/to/file.ext
    ```
    Trunk.Storage.S3.save("path/to/", "file.ext", "/tmp/uploaded_file.ext", bucket: "my-bucket")
    """
    @spec save(
            directory :: String.t(),
            filename :: String.t(),
            source_path :: String.t(),
            opts :: keyword
          ) :: :ok | {:error, :file.posix()}
    def save(directory, filename, source_path, opts \\ []) do
      key = directory |> Path.join(filename)
      bucket = Keyword.fetch!(opts, :bucket)
      ex_aws_opts = Keyword.get(opts, :ex_aws, [])
      save_opts = Keyword.drop(opts, [:bucket, :ex_aws])

      with {:ok, source_data} <- File.read(source_path),
           {:ok, _result} <- put_object(bucket, key, source_data, save_opts, ex_aws_opts) do
        :ok
      else
        error -> error
      end
    end

    defp put_object(bucket, key, source_data, storage_opts, ex_aws_opts) do
      bucket
      |> ExAws.S3.put_object(key, source_data, storage_opts)
      |> ExAws.request(ex_aws_opts)
    end

    @doc ~S"""
    Copies the file within Amazon S3.

    - `directory` - The relative directory within which to find the file (will be combined with the `filename` to form the source S3 object key).
    - `filename` - The name of the file to be copied from (will be combined with the `directory` to form the source S3 object key).
    - `to_directory` - The relative directory within which to copy the file (will be combined with the `to_filename` to form the destination S3 object key).
    - `to_filename` - The name of the file to be copied to (will be combined with the `to_directory` to form the destination S3 object key).
    - `opts` - The options for the storage system
      - `path:` (required) The base path within which to save files
      - `acl:` (optional) The file mode to store the file (accepts octal `0o644` or string `"0644"`). See `File.chmod/2` for more info.

    ## Example:
    The file will be copied from s3.amazonaws.com/my-bucket/path/to/file.ext to s3.amazonaws.com/my-bucket/copied/to/file.copy
    ```
    Trunk.Storage.S3.copy("path/to/", "file.ext", "copied/to/", "file.copy", bucket: "my-bucket")
    """
    @spec copy(
            directory :: String.t(),
            filename :: String.t(),
            to_directory :: String.t(),
            to_filename :: String.t(),
            opts :: keyword
          ) :: :ok | {:error, :file.posix()}
    def copy(directory, filename, to_directory, to_filename, opts \\ []) do
      key = directory |> Path.join(filename)
      to_key = to_directory |> Path.join(to_filename)
      bucket = Keyword.fetch!(opts, :bucket)
      ex_aws_opts = Keyword.get(opts, :ex_aws, [])

      copy_opts =
        opts
        |> Keyword.drop([:bucket, :ex_aws])
        |> Keyword.put(:metadata_directive, :REPLACE)

      with {:ok, _result} <- copy_object(bucket, key, to_key, copy_opts, ex_aws_opts) do
        :ok
      else
        error -> error
      end
    end

    defp copy_object(bucket, key, to_key, storage_opts, ex_aws_opts) do
      bucket
      |> ExAws.S3.put_object_copy(to_key, bucket, key, storage_opts)
      |> ExAws.request(ex_aws_opts)
    end

    def retrieve(directory, filename, destination_path, opts \\ []) do
      key = directory |> Path.join(filename)
      bucket = Keyword.fetch!(opts, :bucket)
      ex_aws_opts = Keyword.get(opts, :ex_aws, [])

      {:ok, %{body: data}} = get_object(bucket, key, ex_aws_opts)
      File.write(destination_path, data, [:binary, :write])
    end

    defp get_object(bucket, key, ex_aws_opts) do
      bucket
      |> ExAws.S3.get_object(key)
      |> ExAws.request(ex_aws_opts)
    end

    @doc ~S"""
    Deletes the file from Amazon S3.

    - `directory` - The directory (will be combined with the `filename` to form the S3 object key.
    - `filename` - The name of the file (will be combined with the `directory` to form the S3 object key.
    - `opts` - The options for the storage system
      - `bucket:` (required) The S3 bucket in which to store the object
      - `ex_aws:` (optional) override options for `ex_aws`

    ## Example:
    The file will be removed from s3.amazonaws.com/my-bucket/path/to/file.ext
    ```
    Trunk.Storage.S3.delete("path/to/", "file.ext", bucket: "my-bucket")
    """
    @spec delete(String.t(), String.t(), keyword) :: :ok | {:error, :file.posix()}
    def delete(directory, filename, opts \\ []) do
      key = directory |> Path.join(filename)
      bucket = Keyword.fetch!(opts, :bucket)
      ex_aws_opts = Keyword.get(opts, :ex_aws, [])

      bucket
      |> ExAws.S3.delete_object(key)
      |> ExAws.request(ex_aws_opts)
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    end

    @doc ~S"""
    Generates a URL to the S3 object

    - `directory` - The directory (will be combined with the `filename` to form the S3 object key.
    - `filename` - The name of the file (will be combined with the `directory` to form the S3 object key.
    - `opts` - The options for the storage system
      - `bucket:` (required) The S3 bucket in which to store the object.
      - `virtual_host:` (optional) boolean indicator whether to generate a virtual host style URL or not.
      - `signed:` (optional) boolean whether to sign the URL or not.
      - `ex_aws:` (optional) override options for `ex_aws`

    ## Example:
    ```
    Trunk.Storage.S3.build_url("path/to", "file.ext", bucket: "my-bucket")
    #=> "https://s3.amazonaws.com/my-bucket/path/to/file.ext"
    Trunk.Storage.S3.build_url("path/to", "file.ext", bucket: "my-bucket", virtual_host: true)
    #=> "https://my-bucket.s3.amazonaws.com/path/to/file.ext"
    Trunk.Storage.S3.build_url("path/to", "file.ext", bucket: "my-bucket", signed: true)
    #=> "https://s3.amazonaws.com/my-bucket/path/to/file.ext?X-Amz-Algorithm=AWS4-HMAC-SHA256&…"
    ```
    """
    def build_uri(directory, filename, opts \\ []) do
      key = directory |> Path.join(filename)
      bucket = Keyword.fetch!(opts, :bucket)
      ex_aws_opts = Keyword.get(opts, :ex_aws, [])

      config = ExAws.Config.new(:s3, ex_aws_opts)
      {:ok, url} = ExAws.S3.presigned_url(config, :get, bucket, key, opts)

      if Keyword.get(opts, :signed, false) do
        url
      else
        uri = URI.parse(url)
        %{uri | query: nil} |> URI.to_string()
      end
    end
  end
end
