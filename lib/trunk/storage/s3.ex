defmodule Trunk.Storage.S3 do
  @moduledoc """
  A `Trunk.Storage` implementation for Amazon’s S3 service.
  """

  @behaviour Trunk.Storage

  @doc ~S"""
  Saves the file to Amazon S3.

  - `directory` - The directory (will be combined with the `filename` to form the S3 key.
  - `filename` - The name of the file (will be combined with the `directory` to form the S3 key.
  - `source_path` - The full path to the file to be stored. This is a path to the uploaded file or a temporary file that has undergone transformation
  - `opts` - The options for the storage system
    - `bucket:` (required) The S3 bucket in which to store the object
    - `ex_aws:` (optional) override options for `ex_aws`

  ## Example:
  The file will be saved to s3.amazonaws.com/my-bucket/path/to/file.ext
  ```
  Trunk.Storage.S3.save("path/to/", "file.ext", "/tmp/uploaded_file.ext", bucket: "my-bucket")
  """
  @spec save(String.t, String.t, String.t, keyword) :: :ok | {:error, :file.posix}
  def save(directory, filename, source_path, opts \\ []) do
    key = directory |> Path.join(filename)
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])
    # {:ok, :done} =
    #   source_path
    #   |> ExAws.S3.Upload.stream_file
    #   |> ExAws.S3.upload(bucket, key)
    #   |> ExAws.request(Keyword.get(opts, :ex_aws))

    with {:ok, source_data} <- File.read(source_path),
         {:ok, _result} <- put_object(bucket, key, source_data, ex_aws_opts) do
      :ok
    else
      error -> error
    end
  end

  defp put_object(bucket, key, source_data, ex_aws_opts) do
    bucket
    |> ExAws.S3.put_object(key, source_data)
    |> ExAws.request(ex_aws_opts)
  end

  @doc ~S"""
  Deletes the file from Amazon S3.

  - `directory` - The directory (will be combined with the `filename` to form the S3 key.
  - `filename` - The name of the file (will be combined with the `directory` to form the S3 key.
  - `opts` - The options for the storage system
    - `bucket:` (required) The S3 bucket in which to store the object
    - `ex_aws:` (optional) override options for `ex_aws`

  ## Example:
  The file will be removed from s3.amazonaws.com/my-bucket/path/to/file.ext
  ```
  Trunk.Storage.S3.delete("path/to/", "file.ext", bucket: "my-bucket")
  """
  @spec delete(String.t, String.t, keyword) :: :ok | {:error, :file.posix}
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

  - `directory` - The directory (will be combined with the `filename` to form the S3 key.
  - `filename` - The name of the file (will be combined with the `directory` to form the S3 key.
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
      %{uri | query: nil} |> URI.to_string
    end
  end
end
