defmodule Trunk.Storage.S3Test do
  use ExUnit.Case, async: false # Playing with global scope - S3

  alias Trunk.Storage.S3

  @bucket System.get_env("TRUNK_TEST_S3_BUCKET") || "trunk-test"

  setup do
    fixtures_path = Path.join(__DIR__, "../fixtures")

    s3_opts = [
      bucket: @bucket,
      ex_aws: [
        access_key_id: System.get_env("TRUNK_TEST_S3_ACCESS_KEY"),
        secret_access_key: System.get_env("TRUNK_TEST_S3_SECRET_ACCESS_KEY"),
        region: "eu-west-1",
        # debug_requests: true,
      ]
    ]

    {:ok, fixtures_path: fixtures_path, s3_opts: s3_opts}
  end

  describe "save/4" do
    @tag :s3
    test "successfully save a file", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      assert :ok = S3.save("trunk/new/dir", "new-coffee.jpg", source_path, s3_opts)
      assert file_saved?("trunk/new/dir/new-coffee.jpg", s3_opts)
      remove_file("trunk/new/dir/new-coffee.jpg", s3_opts)
    end

    @tag :s3
    test "error reading source file", %{fixtures_path: fixtures_path} do
      assert {:error, :enoent} = S3.save("trunk/new/dir", "new-coffee.jpg", Path.join(fixtures_path, "wrong.jpg"), bucket: ["wrong-bucket"])
    end

    @tag :s3
    test "error with S3 bucket", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :bucket, "wrong-bucket-#{System.unique_integer([:positive, :monotonic])}")

      assert {:error, {:http_error, 404, _}} = S3.save("new/dir", "new-coffee.jpg", Path.join(fixtures_path, "coffee.jpg"), s3_opts)
    end
  end

  describe "delete/3" do
    @tag :s3
    test "successfully remove a file", %{fixtures_path: fixtures_path, s3_opts: s3_opts} do
      source_path = Path.join(fixtures_path, "coffee.jpg")
      assert :ok = S3.save("trunk/new/dir", "new-coffee.jpg", source_path, s3_opts)
      assert file_saved?("trunk/new/dir/new-coffee.jpg", s3_opts)
      assert :ok = S3.delete("trunk/new/dir", "new-coffee.jpg", s3_opts)
      refute file_saved?("trunk/new/dir/new-coffee.jpg", s3_opts)
      assert :ok = S3.delete("trunk/new/dir", "new-coffee.jpg", s3_opts) # Can remove the file again without error
    end

    @tag :s3
    test "error with S3 bucket", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :bucket, "wrong-bucket-#{System.unique_integer([:positive, :monotonic])}")

      assert {:error, {:http_error, 404, _}} = S3.delete("new/dir", "new-coffee.jpg", s3_opts)
    end
  end

  describe "build_url/3" do
    @tag :s3
    test "it returns a url", %{s3_opts: s3_opts} do
      assert S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) == "https://s3-eu-west-1.amazonaws.com/#{@bucket}/trunk/new/dir/new-coffee.jpg"
    end

    @tag :s3
    test "it returns a signed url", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :signed, true)
      url = S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) |> URI.parse
      assert %URI{host: "s3-eu-west-1.amazonaws.com", path: "/#{@bucket}/trunk/new/dir/new-coffee.jpg"} = url
      assert url.query =~ ~r/X-Amz-Algorithm=AWS4-HMAC-SHA256/
    end

    @tag :s3
    test "it returns a url with a virtual host", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :virtual_host, true)
      assert S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) == "https://#{@bucket}.s3-eu-west-1.amazonaws.com/trunk/new/dir/new-coffee.jpg"
    end

    @tag :s3
    test "it returns a signed url with a virtual host", %{s3_opts: s3_opts} do
      s3_opts = Keyword.put(s3_opts, :virtual_host, true)
      s3_opts = Keyword.put(s3_opts, :signed, true)
      url = S3.build_uri("trunk/new/dir", "new-coffee.jpg", s3_opts) |> URI.parse
      assert %URI{host: "#{@bucket}.s3-eu-west-1.amazonaws.com", path: "/trunk/new/dir/new-coffee.jpg"} = url
      assert url.query =~ ~r/X-Amz-Algorithm=AWS4-HMAC-SHA256/
    end
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

  defp remove_file(path, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])

    {:ok, _} =
      bucket
      |> ExAws.S3.delete_object(path)
      |> ExAws.request(ex_aws_opts)
  end
end
