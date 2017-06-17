defmodule Trunk.Storage.FilesystemTest do
  use ExUnit.Case, async: false

  alias Trunk.Storage.Filesystem

  describe "save/4" do
    setup do
      # Delete and recreate on setup rather than create on setup and create on exit
      #   because then the files can be visually inspected after a test
      output_path = Path.join(__DIR__, "../output")
      File.rm_rf!(output_path)
      File.mkdir!(output_path)

      fixtures_path = Path.join(__DIR__, "../fixtures")

      {:ok, output_path: output_path, fixtures_path: fixtures_path}
    end

    test "successfully save a file", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert :ok = Filesystem.save("new/dir", "new-coffee.jpg", Path.join(fixtures_path, "coffee.jpg"), path: output_path)
      assert File.exists?(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "error saving file", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert {:error, :enoent} = Filesystem.save("new/dir", "new-coffee.jpg", Path.join(fixtures_path, "wrong.jpg"), path: output_path)
    end
  end

  describe "build_url/3" do
    test "it returns a relative url" do
      assert Filesystem.build_uri("new/dir", "new-coffee.jpg") == "new/dir/new-coffee.jpg"
      assert Filesystem.build_uri("new/dir", "new-coffee.jpg", base_uri: "http://example.com") == "http://example.com/new/dir/new-coffee.jpg"
      assert Filesystem.build_uri("new/dir", "new-coffee.jpg", base_uri: "http://example.com/uploads/") == "http://example.com/uploads/new/dir/new-coffee.jpg"
      assert Filesystem.build_uri("new/dir", "new-coffee.jpg", base_uri: "/uploads/") == "/uploads/new/dir/new-coffee.jpg"
    end
  end
end
