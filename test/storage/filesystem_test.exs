defmodule Trunk.Storage.FilesystemTest do
  use ExUnit.Case, async: true

  alias Trunk.Storage.Filesystem

  setup do
    {:ok, output_path} = Briefly.create(directory: true)
    fixtures_path = Path.join(__DIR__, "../fixtures")

    {:ok, output_path: output_path, fixtures_path: fixtures_path}
  end

  describe "save/4" do
    test "successfully save a file", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert :ok =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 path: output_path
               )

      assert File.exists?(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "will save a file with specific access permissions (string)", %{
      output_path: output_path,
      fixtures_path: fixtures_path
    } do
      assert :ok =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 path: output_path,
                 acl: "0600"
               )

      assert "600" == print_file_permissions(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "ignores unparsable acl", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert :ok =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 path: output_path,
                 acl: "wat"
               )

      assert :ok =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 path: output_path,
                 acl: :private
               )
    end

    test "will save a file with specific access permissions (number)", %{
      output_path: output_path,
      fixtures_path: fixtures_path
    } do
      assert :ok =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 path: output_path,
                 acl: 0o640
               )

      assert "640" == print_file_permissions(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "error saving file", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert {:error, :enoent} =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "wrong.jpg"),
                 path: output_path
               )
    end
  end

  describe "copy/4" do
    setup %{output_path: output_path, fixtures_path: fixtures_path} do
      source_path = "old/dir"
      path = Path.join([output_path, source_path])
      File.mkdir_p!(path)
      File.cp!(Path.join(fixtures_path, "coffee.jpg"), Path.join(path, "coffee.jpg"))

      %{source_path: source_path}
    end

    test "successfully copy a file", %{output_path: output_path, source_path: source_path} do
      assert :ok =
               Filesystem.copy(
                 source_path,
                 "coffee.jpg",
                 "new/dir",
                 "new-coffee.jpg",
                 path: output_path
               )

      assert File.exists?(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "will copy a file with specific access permissions (string)", %{
      output_path: output_path,
      source_path: source_path
    } do
      assert :ok =
               Filesystem.copy(
                 source_path,
                 "coffee.jpg",
                 "new/dir",
                 "new-coffee.jpg",
                 path: output_path,
                 acl: "0600"
               )

      assert "600" == print_file_permissions(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "ignores unparsable acl", %{output_path: output_path, source_path: source_path} do
      assert :ok =
               Filesystem.copy(
                 source_path,
                 "coffee.jpg",
                 "new/dir",
                 "new-coffee.jpg",
                 path: output_path,
                 acl: "wat"
               )

      assert :ok =
               Filesystem.copy(
                 source_path,
                 "coffee.jpg",
                 "new/dir",
                 "new-coffee.jpg",
                 path: output_path,
                 acl: :private
               )
    end

    test "will copy a file with specific access permissions (number)", %{
      output_path: output_path,
      source_path: source_path
    } do
      assert :ok =
               Filesystem.copy(
                 source_path,
                 "coffee.jpg",
                 "new/dir",
                 "new-coffee.jpg",
                 path: output_path,
                 acl: 0o640
               )

      assert "640" == print_file_permissions(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end

    test "error copying a file", %{output_path: output_path, source_path: source_path} do
      assert {:error, :enoent} =
               Filesystem.copy(
                 source_path,
                 "wrong.jpg",
                 "new/dir",
                 "new-coffee.jpg",
                 path: output_path
               )
    end
  end

  describe "retrieve/4" do
    test "successfully retrieving a file", %{
      output_path: output_path,
      fixtures_path: fixtures_path
    } do
      refute File.exists?(Path.join(output_path, "coffee.jpg"))

      assert :ok =
               Filesystem.retrieve(
                 "",
                 "coffee.jpg",
                 Path.join(output_path, "coffee.jpg"),
                 path: fixtures_path
               )

      assert File.exists?(Path.join(output_path, "coffee.jpg"))
    end

    test "error retrieving a file", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert {:error, :enoent} =
               Filesystem.retrieve(
                 "",
                 "wrong.jpg",
                 Path.join(output_path, "coffee.jpg"),
                 path: fixtures_path
               )
    end
  end

  describe "delete/3" do
    test "successfully save a file", %{output_path: output_path, fixtures_path: fixtures_path} do
      assert :ok =
               Filesystem.save(
                 "new/dir",
                 "new-coffee.jpg",
                 Path.join(fixtures_path, "coffee.jpg"),
                 path: output_path
               )

      assert File.exists?(Path.join(output_path, "new/dir/new-coffee.jpg"))
      assert :ok = Filesystem.delete("new/dir", "new-coffee.jpg", path: output_path)
      refute File.exists?(Path.join(output_path, "new/dir/new-coffee.jpg"))
    end
  end

  describe "build_url/3" do
    test "it returns a relative url" do
      assert Filesystem.build_uri("new/dir", "new-coffee.jpg") == "new/dir/new-coffee.jpg"

      assert Filesystem.build_uri("new/dir", "new-coffee.jpg", base_uri: "http://example.com") ==
               "http://example.com/new/dir/new-coffee.jpg"

      assert Filesystem.build_uri(
               "new/dir",
               "new-coffee.jpg",
               base_uri: "http://example.com/uploads/"
             ) == "http://example.com/uploads/new/dir/new-coffee.jpg"

      assert Filesystem.build_uri("new/dir", "new-coffee.jpg", base_uri: "/uploads/") ==
               "/uploads/new/dir/new-coffee.jpg"
    end
  end

  defp print_file_permissions(path) do
    require Bitwise
    {:ok, %{mode: mode}} = File.stat(path)
    :io_lib.format('~.8B', [Bitwise.band(mode, 0o777)]) |> to_string
  end
end
