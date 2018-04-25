defmodule Trunk.Storage.S3Test do
  # Playing with global scope - S3
  use ExUnit.Case, async: false

  alias Trunk.Storage.S3

  @bucket System.get_env("TRUNK_TEST_S3_BUCKET") || "trunk-test"

  setup do
    fixtures_path = Path.join(__DIR__, "../fixtures")

    s3_opts = [
      bucket: @bucket,
      ex_aws: [
        access_key_id: System.get_env("TRUNK_TEST_S3_ACCESS_KEY"),
        secret_access_key: System.get_env("TRUNK_TEST_S3_SECRET_ACCESS_KEY"),
        region: "eu-west-1"
        # debug_requests: true,
      ]
    ]

    {:ok, fixtures_path: fixtures_path, s3_opts: s3_opts}
  end

  describe "save/4" do
    @tag :s3
    test "successfully save a file", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      dir = "dir/#{:rand.uniform(123)}"
      assert :ok = S3.save(dir, "new-coffee.jpg", source_path, s3_opts)
      assert file_saved?("#{dir}/new-coffee.jpg", s3_opts)
      remove_file("#{dir}/new-coffee.jpg", s3_opts)
    end

    @tag :s3
    test "successfully save a file with default permissions", %{
      fixtures_path: fixtures_path,
      s3_opts: s3_opts
    } do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      dir = "dir/#{:rand.uniform(123)}"
      assert :ok = S3.save(dir, "new-coffee.jpg", source_path, s3_opts)
      assert file_private?(dir, "new-coffee.jpg", s3_opts)
      remove_file("#{dir}/new-coffee.jpg", s3_opts)
    end

    @tag :s3
    test "successfully save a file with set permissions", %{
      fixtures_path: fixtures_path,
      s3_opts: s3_opts
    } do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      dir = "dir/#{:rand.uniform(123)}"

      assert :ok =
               S3.save(
                 dir,
                 "new-coffee.jpg",
                 source_path,
                 Keyword.merge(s3_opts, acl: :public_read)
               )

      assert file_public?(dir, "new-coffee.jpg", s3_opts)
      remove_file("#{dir}/new-coffee.jpg", s3_opts)
    end

    @tag :s3
    test "successfully save a file with specific headers", %{
      fixtures_path: fixtures_path,
      s3_opts: s3_opts
    } do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      dir = "dir/#{:rand.uniform(123)}"

      assert :ok =
               S3.save(
                 dir,
                 "new-coffee.jpg",
                 source_path,
                 Keyword.merge(
                   s3_opts,
                   content_type: "image/wat",
                   content_disposition: "attachment;filename=my-coffee.jpg"
                 )
               )

      headers = get_headers("#{dir}/new-coffee.jpg", s3_opts)
      assert {"Content-Type", "image/wat"} in headers
      assert {"Content-Disposition", "attachment;filename=my-coffee.jpg"} in headers
      remove_file("#{dir}/new-coffee.jpg", s3_opts)
    end

    @tag :s3
    test "error reading source file", %{fixtures_path: fixtures_path} do
      assert {:error, :enoent} =
               S3.save(
                 "trunk/new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "wrong.jpg"),
                 bucket: ["wrong-bucket"]
               )
    end

    @tag :s3
    test "error with S3 bucket", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      s3_opts =
        Keyword.put(
          s3_opts,
          :bucket,
          "wrong-bucket-#{System.unique_integer([:positive, :monotonic])}"
        )

      assert {:error, {:http_error, 404, _}} =
               S3.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 s3_opts
               )
    end
  end

  describe "retrieve/4" do
    @tag :s3
    test "successfully save a file", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      dir = "dir/#{:rand.uniform(123)}"
      assert :ok = S3.save(dir, "new-coffee.jpg", source_path, s3_opts)
      assert file_saved?("#{dir}/new-coffee.jpg", s3_opts)

      {:ok, output_path} = Briefly.create(extname: ".jpg")
      assert :ok = S3.retrieve(dir, "new-coffee.jpg", output_path, s3_opts)

      assert File.read!(output_path) == File.read!(source_path)
    end
  end

  describe "delete/3" do
    @tag :s3
    test "successfully remove a file", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      dir = "dir/#{:rand.uniform(123)}"
      assert :ok = S3.save(dir, "new-coffee.jpg", source_path, s3_opts)
      assert file_saved?("#{dir}/new-coffee.jpg", s3_opts)
      assert :ok = S3.delete(dir, "new-coffee.jpg", s3_opts)
      refute file_saved?("#{dir}/new-coffee.jpg", s3_opts)
      # Can remove the file again without error
      assert :ok = S3.delete(dir, "new-coffee.jpg", s3_opts)
    end

    @tag :s3
    test "error with S3 bucket", %{s3_opts: s3_opts} do
      s3_opts =
        Keyword.put(
          s3_opts,
          :bucket,
          "wrong-bucket-#{System.unique_integer([:positive, :monotonic])}"
        )

      assert {:error, {:http_error, 404, _}} = S3.delete("new/dir", "new-coffee.jpg", s3_opts)
    end
  end

  describe "build_url/3" do
    @tag :s3
    test "it returns a url", %{s3_opts: s3_opts} do
      assert S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) ==
               "https://s3-eu-west-1.amazonaws.com/#{@bucket}/trunk/new/dir/new-coffee.jpg"
    end

    @tag :s3
    test "it returns a signed url", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :signed, true)
      url = S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) |> URI.parse()

      path = "/#{@bucket}/trunk/new/dir/new-coffee.jpg"
      assert match?(%URI{host: "s3-eu-west-1.amazonaws.com", path: ^path}, url)

      assert url.query =~ ~r/X-Amz-Algorithm=AWS4-HMAC-SHA256/
    end

    @tag :s3
    test "it returns a url with a virtual host", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :virtual_host, true)

      assert S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) ==
               "https://#{@bucket}.s3-eu-west-1.amazonaws.com/trunk/new/dir/new-coffee.jpg"
    end

    @tag :s3
    test "it returns a signed url with a virtual host", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :virtual_host, true)
      s3_opts = Keyword.put(s3_opts, :signed, true)
      url = S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) |> URI.parse()

      host = "#{@bucket}.s3-eu-west-1.amazonaws.com"
      assert match?(%URI{host: ^host, path: "/trunk/new/dir/new-coffee.jpg"}, url)

      assert url.query =~ ~r/X-Amz-Algorithm=AWS4-HMAC-SHA256/
    end
  end

  # Make a public request for the file to check it fails followed by a signed request to check it succeeds
  defp file_private?(dir, file_name, opts) do
    url = S3.build_uri(dir, file_name, Keyword.merge(opts, signed: false))
    {:ok, status_code, _headers, _body} = :hackney.get(url, [], <<>>, with_body: true)

    if status_code == 403 do
      url = S3.build_uri(dir, file_name, Keyword.merge(opts, signed: true))
      {:ok, status_code, _headers, _body} = :hackney.get(url, [], <<>>, with_body: true)
      status_code == 200
    else
      false
    end
  end

  # Make a public request for the file to check it succeeds
  defp file_public?(dir, file_name, opts) do
    url = S3.build_uri(dir, file_name, Keyword.merge(opts, signed: false))
    {:ok, status_code, _headers, _body} = :hackney.get(url, [], <<>>, with_body: true)
    status_code == 200
  end

  defp file_saved?(path, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])

    result =
      bucket
      |> ExAws.S3.head_object(path)
      |> ExAws.request(ex_aws_opts)

    case result do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp get_headers(path, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])

    {:ok, %{headers: headers}} =
      bucket
      |> ExAws.S3.head_object(path)
      |> ExAws.request(ex_aws_opts)

    headers
  end

  defp remove_file(path, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])

    {:ok, _} =
      bucket
      |> ExAws.S3.delete_object(path)
      |> ExAws.request(ex_aws_opts)
  end
end
