defmodule TrunkTest do
  use ExUnit.Case, async: false # We are playing with global scope (filesystem)
  doctest Trunk

  defmodule TestTrunk do
    output_path = Path.join(__DIR__, "output")
    use Trunk, versions: [:original, :thumb, :png_thumb, :function],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: unquote(output_path)]

    def preprocess(%Trunk.State{extname: extname} = state) do
      if String.downcase(extname) in [".png", ".jpg", ".jpeg"] do
        {:ok, state}
      else
        {:error, "Invalid file"}
      end
    end

    def storage_dir(%Trunk.State{scope: %{id: id}}, _version),
      do: "#{id}"
    def storage_dir(_state, _version),
      do: ""

    def filename(%Trunk.State{rootname: rootname, extname: extname}, :thumb),
      do: rootname <> "_thumb" <> extname
    def filename(%Trunk.State{rootname: rootname}, :png_thumb),
      do: rootname <> "_thumb.png"
    def filename(%Trunk.State{rootname: rootname}, :function),
      do: rootname <> ".pdf"
    def filename(junk, version), do: super(junk, version)

    def transform(_, :thumb),
      do: {:convert, "-strip -thumbnail 100x100>"}
    def transform(_, :png_thumb),
      do: {:convert, "-strip -thumbnail 100x100>", :png} # The file is converted before asking for the filename (so you can be really fancy)
    def transform(_, :transform_error),
      do: {:convert, "-strip -wrongOption"}
    def transform(_, :function),
      do: fn(input) ->
        {:ok, temp_file} = Briefly.create(extname: ".pdf")
        {_output, 0} = System.cmd("convert", [input, temp_file])
        {:ok, temp_file}
      end
    def transform(junk, version), do: super(junk, version)
  end

  setup do
    # Delete and recreate on setup rather than create on setup and create on exit
    #   because then the files can be visually inspected after a test
    output_path = Path.join(__DIR__, "output")
    File.rm_rf!(output_path)
    File.mkdir!(output_path)

    {:ok, output_path: output_path}
  end

  describe "store/1" do
    test "store", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      {:ok, %Trunk.State{}} = TestTrunk.store(original_file)
      # |> IO.inspect

      assert geometry(original_file) == geometry(Path.join(output_path, "coffee.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.png"))
      assert File.exists?(Path.join(output_path, "coffee.pdf"))
    end
  end

  describe "store/2" do
    Enum.map([true, false], fn(async) ->
      test "store with options async:#{async}", %{output_path: output_path} do
        original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        {:ok, %Trunk.State{}} = TestTrunk.store(original_file,
          async: unquote(async), versions: [:original, :thumb])

        assert geometry(original_file) == geometry(Path.join(output_path, "coffee.jpg"))
        assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.jpg"))
        refute File.exists?(Path.join(output_path, "coffee_thumb.png"))
      end
    end)
  end

  describe "store/3" do
    Enum.map([false, true], fn(async) ->
      test "store with scope and options async:#{async}", %{output_path: output_path} do
        original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        {:ok, %Trunk.State{}} = TestTrunk.store(original_file,
          %{id: 42},
          async: unquote(async), versions: [:original, :thumb])

        assert geometry(original_file) == geometry(Path.join(output_path, "42/coffee.jpg"))
        assert "78x100" == geometry(Path.join(output_path, "42/coffee_thumb.jpg"))
      end
    end)
  end

  describe "store error handling" do
    Enum.map([true, false], fn(async) ->
      test "error with transform async:#{async}" do
        original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        assert {:error, %Trunk.State{errors: errors}} = TestTrunk.store(original_file,
          %{id: 42},
          async: unquote(async), versions: [:transform_error])
        %{transform_error: {:transform, error_msg}} = errors
        assert error_msg =~ ~r/unrecognized option/
      end

      test "preprocessing error async:#{async}" do
        original_file = Path.join(__DIR__, "fixtures/coffee.doc")
        assert {:error, "Invalid file"} = TestTrunk.store(original_file,
          %{id: 42}, async: unquote(async))
      end
    end)
  end

  describe "url/1" do
    test "with a map" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}) == "coffee.jpg"
    end

    test "with just a filename" do
      assert TestTrunk.url("coffee.jpg") == "coffee.jpg"
    end
  end

  describe "url/2" do
    test "with a map and a version" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}, :png_thumb) == "coffee_thumb.png"
    end

    test "with a map and a scope" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}, %{id: 42}) == "42/coffee.jpg"
    end

    test "with a map and options" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/coffee.jpg"
    end

    test "with just a filename and a version" do
      assert TestTrunk.url("coffee.jpg", :thumb) == "coffee_thumb.jpg"
    end

    test "with just a filename and a scope" do
      assert TestTrunk.url("coffee.jpg", %{id: 42}) == "42/coffee.jpg"
    end

    test "with just a filename and options" do
      assert TestTrunk.url("coffee.jpg", storage_opts: [base_uri: "http://example.com"]) == "http://example.com/coffee.jpg"
    end
  end

  describe "url/3" do
    test "with a map, a version, and options" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}, :png_thumb, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/coffee_thumb.png"
    end

    test "with a map, a scope, and options" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}, %{id: 42}, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/42/coffee.jpg"
    end

    test "with just a filename, a version, and options" do
      assert TestTrunk.url("coffee.jpg", :thumb, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/coffee_thumb.jpg"
    end

    test "with just a filename, a scope, and options" do
      assert TestTrunk.url("coffee.jpg", %{id: 42}, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/42/coffee.jpg"
    end
  end

  describe "url/4" do
    test "with a map" do
      assert TestTrunk.url(%{filename: "coffee.jpg"}, %{id: 42}, :original, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/42/coffee.jpg"
      assert TestTrunk.url(%{filename: "coffee.jpg"}, %{id: 42}, :png_thumb, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/42/coffee_thumb.png"
    end

    test "with just a filename" do
      assert TestTrunk.url("coffee.jpg", %{id: 42}, :original, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/42/coffee.jpg"
      assert TestTrunk.url("coffee.jpg", %{id: 42}, :thumb, storage_opts: [base_uri: "http://example.com"]) == "http://example.com/42/coffee_thumb.jpg"
    end
  end

  defp geometry(path) do
    {file_info, 0} = System.cmd("identify", [path], stderr_to_stdout: true)
    hd(Regex.run(~r/(\d+)x(\d+)/, file_info))
  end
end
