defmodule TrunkTest do
  use ExUnit.Case, async: false # We are playing with global scope (filesystem)
  doctest Trunk

  defmodule TestTrunk do
    output_path = Path.join(__DIR__, "output")
    use Trunk, versions: [:original, :thumb, :png_thumb, :function],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: unquote(output_path)]

    def preprocess(%Trunk.State{lower_extname: extname} = state) do
      if extname in [".png", ".jpg", ".jpeg"] do
        {:ok, state}
      else
        {:error, "Invalid file"}
      end
    end

    def storage_opts(%Trunk.State{}, _version), do: [acl: "0600"]

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
      do: {:convert, fn(input, output) -> ["-density", "300", input, "-flatten", "-strip", "-thumbnail", "200x200>", output] end, :jpg}
    def transform(junk, version), do: super(junk, version)
  end

  defmodule Md5Trunk do
    output_path = Path.join(__DIR__, "output")
    use Trunk, versions: [:original, :thumb],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: unquote(output_path)]

    def preprocess(%Trunk.State{path: path} = state) do
      hash = :crypto.hash(:md5, File.read!(path)) |> Base.encode16(case: :lower)
      {:ok, %{state | assigns: Map.put(state.assigns, :hash, hash)}}
    end

    def postprocess(%Trunk.VersionState{} = version_state, :original, _state),
      do: {:ok, version_state}
    def postprocess(%Trunk.VersionState{temp_path: temp_path} = version_state, _version, _state) do
      hash = :crypto.hash(:md5, File.read!(temp_path)) |> Base.encode16(case: :lower)
      {:ok, Trunk.VersionState.assign(version_state, :hash, hash)}
    end

    def storage_dir(%Trunk.State{assigns: %{hash: hash}}, :original),
      do: "#{hash}"
    def storage_dir(%Trunk.State{assigns: %{hash: hash}} = state, version),
      do: "#{hash}/#{Trunk.State.get_version_assign(state, version, :hash)}"

    def transform(_, :thumb),
      do: {:convert, "-strip -thumbnail 100x100>"}
    def transform(junk, version), do: super(junk, version)
  end

  defmodule ValidateTrunk do
    output_path = Path.join(__DIR__, "output")
    use Trunk, versions: [:original],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: unquote(output_path)]

    validate_file_extensions ~w[.jpg .jpeg .png]
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
    test "store with a simple file path", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      {:ok, %Trunk.State{}} = TestTrunk.store(original_file)
      # |> IO.inspect

      assert geometry(original_file) == geometry(Path.join(output_path, "coffee.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.png"))
      assert File.exists?(Path.join(output_path, "coffee.pdf"))
    end

    test "store with a %Plug.Upload{} struct", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      upload = %Plug.Upload{filename: "coffee.jpg", path: original_file}
      {:ok, %Trunk.State{}} = TestTrunk.store(upload)
      # |> IO.inspect

      assert geometry(original_file) == geometry(Path.join(output_path, "coffee.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.png"))
      assert File.exists?(Path.join(output_path, "coffee.pdf"))
    end

    test "store with a %{filename: filename, binary: binary} map", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      upload = %{filename: "coffee.jpg", binary: File.read!(original_file)}
      {:ok, %Trunk.State{}} = TestTrunk.store(upload)
      # |> IO.inspect

      assert geometry(original_file) == geometry(Path.join(output_path, "coffee.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "coffee_thumb.png"))
      assert File.exists?(Path.join(output_path, "coffee.pdf"))
    end

    test "store with a URL", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")

      bypass = Bypass.open
      Bypass.expect bypass, fn conn ->
        assert "/path/to/coffee.jpg" == conn.request_path
        assert "GET" == conn.method
        Plug.Conn.send_file(conn, 200, original_file)
      end

      {:ok, %Trunk.State{}} = TestTrunk.store("http://localhost:#{bypass.port}/path/to/coffee.jpg")

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

      test "post processing async:#{async}", %{output_path: output_path} do
        original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        {:ok, %Trunk.State{assigns: %{hash: hash}, versions: versions}} = Md5Trunk.store(original_file, async: unquote(async))
        %{assigns: %{hash: version_hash}} = versions[:thumb]

        assert geometry(original_file) == geometry(Path.join(output_path, "/#{hash}/coffee.jpg"))
        assert "78x100" == geometry(Path.join(output_path, "/#{hash}/#{version_hash}/coffee_thumb.jpg"))
      end
    end)

    test "store with scope", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      {:ok, %Trunk.State{}} = TestTrunk.store(original_file, %{id: 42})

      assert geometry(original_file) == geometry(Path.join(output_path, "42/coffee.jpg"))
      assert "78x100" == geometry(Path.join(output_path, "42/coffee_thumb.jpg"))
    end
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
        %{transform_error: [transform: error_msg]} = errors
        assert error_msg =~ ~r/unrecognized option/
      end

      test "preprocessing error async:#{async}" do
        original_file = Path.join(__DIR__, "fixtures/coffee.doc")
        assert {:error, "Invalid file"} = TestTrunk.store(original_file,
          %{id: 42}, async: unquote(async))
      end

      test "preprocessing using lower_extname async:#{async}", %{output_path: output_path} do
        source_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        original_file = Path.join(output_path, "source.JPG")
        File.cp(source_file, original_file)
        assert {:ok, _state} = TestTrunk.store(original_file,
          %{id: 42}, async: unquote(async))
      end
    end)
  end

  describe "delete/1" do
    test "it deletes the files from storage", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      {:ok, %Trunk.State{}} = TestTrunk.store(original_file)

      stored_files = Path.join(output_path, "*") |> Path.wildcard

      {:ok, _state} = TestTrunk.delete("coffee.jpg")

      assert Enum.all?(stored_files, fn(path) -> !File.exists?(path) end)

      {:ok, _state} = TestTrunk.delete("coffee.jpg") # It can be run again if files are already deleted.
    end
  end

  describe "delete/2" do
    Enum.each([true, false], fn(async) ->
      test "delete with options async:#{async}", %{output_path: output_path} do
        opts = [async: unquote(async)]

        original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        {:ok, %Trunk.State{}} = TestTrunk.store(original_file, opts)

        stored_files = Path.join(output_path, "*") |> Path.wildcard

        {:ok, _state} = TestTrunk.delete("coffee.jpg", opts)

        assert Enum.all?(stored_files, fn(path) -> !File.exists?(path) end)

        {:ok, _state} = TestTrunk.delete("coffee.jpg", opts) # It can be run again if files are already deleted.
      end
    end)

    test "delete with scope", %{output_path: output_path} do
      original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      {:ok, %Trunk.State{}} = TestTrunk.store(original_file, %{id: 42})

      stored_files = Path.join(output_path, "42/*") |> Path.wildcard

      {:ok, _state} = TestTrunk.delete("coffee.jpg", %{id: 42})

      assert Enum.all?(stored_files, fn(path) -> !File.exists?(path) end)

      {:ok, _state} = TestTrunk.delete("coffee.jpg", %{id: 42}) # It can be run again if files are already deleted.
    end
  end

  describe "delete/3" do
    Enum.map([false, true], fn(async) ->
      test "delete with scope and options async:#{async}", %{output_path: output_path} do
        original_file = Path.join(__DIR__, "fixtures/coffee.jpg")
        opts = [async: unquote(async), versions: [:original, :thumb]]
        {:ok, %Trunk.State{}} = TestTrunk.store(original_file, %{id: 42}, opts)

        stored_files = Path.join(output_path, "42/*") |> Path.wildcard

        {:ok, _state} = TestTrunk.delete("coffee.jpg", %{id: 42}, opts)

        assert Enum.all?(stored_files, fn(path) -> !File.exists?(path) end)

        {:ok, _state} = TestTrunk.delete("coffee.jpg", %{id: 42}, opts) # It can be run again if files are already deleted.
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

  describe "validate_file_extensions/1" do
    test "returns error for invalid extension" do
      original_file = Path.join(__DIR__, "fixtures/coffee.doc")
      assert {:error, :invalid_file} = ValidateTrunk.store(original_file)
    end

    test "does test on lowercase file extension", %{output_path: output_path} do
      source_file = Path.join(__DIR__, "fixtures/coffee.jpg")
      original_file = Path.join(output_path, "source.JPG")
      File.cp(source_file, original_file)
      assert {:ok, _state} = ValidateTrunk.store(original_file)
    end
  end

  defp geometry(path) do
    {file_info, 0} = System.cmd("identify", [path], stderr_to_stdout: true)
    hd(Regex.run(~r/(\d+)x(\d+)/, file_info))
  end
end
