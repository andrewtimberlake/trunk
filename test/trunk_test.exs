defmodule TrunkTest do
  use ExUnit.Case, async: false # We are playing with global scope (filesystem)
  doctest Trunk

  defmodule TestTrunk do
    output_path = Path.join(__DIR__, "output")
    use Trunk, versions: [:original, :thumb, :png_thumb],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: unquote(output_path)]

    def filename(%{rootname: rootname, extname: extname}, :thumb),
      do: rootname <> "_thumb" <> extname
    def filename(%{rootname: rootname}, :png_thumb),
      do: rootname <> "_thumb.png"
    def filename(junk, version), do: super(junk, version)

    def transform(_, :thumb),
      do: {:convert, "-strip -thumbnail 200x200>"}
    def transform(_, :png_thumb),
      do: {:convert, "-strip -thumbnail 200x200>", :png} # The file is converted before asking for the filename (so you can be really fancy)
    def transform(junk, version), do: super(junk, version)

    def storage_dir(%{scope: %{id: id}} = state, version),
      do: "#{id}"
    def storage_dir(_state, _version),
      do: ""

    def validate(state, version)
  end

  setup do
    # Delete and recreate on setup rather than create on setup and create on exit
    #   because then the files can be visually inspected after a test
    output_path = Path.join(__DIR__, "output")
    File.rm_rf!(output_path)
    File.mkdir!(output_path)

    {:ok, output_path: output_path}
  end

  test "store", %{output_path: output_path} do
    {:ok, %Trunk.State{}} = TestTrunk.store(Path.join(__DIR__, "fixtures/coffee.jpg"))
    # |> IO.inspect

    assert File.exists?(Path.join(output_path, "coffee.jpg"))
    assert File.exists?(Path.join(output_path, "coffee_thumb.jpg"))
    assert File.exists?(Path.join(output_path, "coffee_thumb.png"))
  end

  test "store with scope based directory", %{output_path: output_path} do
    {:ok, _state} = TestTrunk.store(Path.join(__DIR__, "fixtures/coffee.jpg"), %{id: 42})
    # |> IO.inspect

    assert File.exists?(Path.join(output_path, "42/coffee.jpg"))
  end

  test "url", %{output_path: output_path} do
    assert TestTrunk.url(%{filename: "coffee.jpg"}) == "coffee.jpg"
    assert TestTrunk.url(%{filename: "coffee.jpg"}, :png_thumb) == "coffee_thumb.png"

    # With just a file name
    assert TestTrunk.url("coffee.jpg", path: output_path) == "coffee.jpg"
    assert TestTrunk.url("coffee.jpg", :thumb, path: output_path) == "coffee_thumb.jpg"
  end

  test "url with scope", %{output_path: output_path} do
    assert TestTrunk.url(%{filename: "coffee.jpg"}, %{id: 42}) == "42/coffee.jpg"
    assert TestTrunk.url(%{filename: "coffee.jpg"}, %{id: 42}, :png_thumb, path: output_path) == "42/coffee_thumb.png"

    # With just a file name
    assert TestTrunk.url("coffee.jpg", %{id: 42}, path: output_path) == "42/coffee.jpg"
    assert TestTrunk.url("coffee.jpg", %{id: 42}, :thumb, path: output_path) == "42/coffee_thumb.jpg"
  end
end
