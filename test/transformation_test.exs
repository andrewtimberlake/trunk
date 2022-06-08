defmodule Trunk.TransformationTest do
  use ExUnit.Case, async: true

  defmodule MultiPagePdfTrunk do
    use Trunk,
      versions: [:original, :thumbnails],
      async: false,
      storage: Trunk.Storage.Filesystem

    @impl true
    def filename(_state, :thumbnails), do: "thumbnail.jpg"
    def filename(%{extname: extname}, version), do: "#{version}#{extname}"

    @impl true
    def transform(_state, :original), do: nil

    def transform(_state, :thumbnails),
      do: fn source_file ->
        {:ok, directory} = Briefly.create(directory: true)
        output_path = Path.join(directory, "out-%02d.jpg")

        args = [
          "-density",
          "300",
          source_file,
          "-strip",
          "+adjoin",
          "-thumbnail",
          "600x600>",
          output_path
        ]

        case System.cmd("convert", args) do
          {_, 0} ->
            {:ok, directory |> Path.join("*") |> Path.wildcard()}

          {output, _} ->
            {:error, output}
        end
      end
  end

  test "convert multi page PDF" do
    fixtures_path = Path.join(__DIR__, "fixtures/")
    original_file = Path.join(fixtures_path, "test-2.pdf")
    {:ok, output_path} = Briefly.create(directory: true)
    {:ok, _state} = MultiPagePdfTrunk.store(original_file, storage_opts: [path: output_path])

    assert File.exists?(Path.join(output_path, "thumbnail.jpg"))
    assert File.exists?(Path.join(output_path, "thumbnail-1.jpg"))
    assert File.exists?(Path.join(output_path, "original.pdf"))
  end
end
