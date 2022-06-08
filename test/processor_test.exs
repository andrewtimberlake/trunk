defmodule Trunk.ProcessorTest do
  use ExUnit.Case, async: true

  alias Trunk.{Processor, State, VersionState}

  describe "transformations" do
    defmodule TestTrunk do
      use Trunk, versions: []

      @impl true
      def transform(_state, :timeout_version), do: fn _ -> Process.sleep(2_000) end
    end

    test "version timeout async:true" do
      assert {:error, %{errors: errors}} =
               Processor.store(%State{
                 module: TestTrunk,
                 versions: %{timeout_version: %VersionState{}},
                 async: true,
                 timeout: 500
               })

      assert %{timeout_version: [processing: :timeout]} = errors
    end

    test "version timeout async:false" do
      assert {:error, %{errors: errors}} =
               Processor.store(%State{
                 module: TestTrunk,
                 versions: %{timeout_version: %VersionState{}},
                 async: false,
                 timeout: 500
               })

      assert :timeout = errors
    end

    test "spaces in file names" do
      original_file = Path.join(__DIR__, "fixtures/coffee_beans.jpg")

      assert {:ok, _version_state} =
               Processor.transform_version(
                 %{transform: {:convert, "-thumbnail 100x100>"}},
                 :version,
                 %State{
                   path: original_file,
                   extname: ".jpg",
                   versions: %{version: %VersionState{}}
                 }
               )
    end

    test "list of arguments" do
      original_file = Path.join(__DIR__, "fixtures/coffee_beans.jpg")

      assert {:ok, _version_state} =
               Processor.transform_version(
                 %{transform: {:convert, ["-thumbnail", "100x100>"]}},
                 :version,
                 %State{
                   path: original_file,
                   extname: ".jpg",
                   versions: %{version: %VersionState{}}
                 }
               )
    end

    test "transformation function" do
      assert {:ok, %{temp_path: "temp_file"}} =
               Processor.transform_version(
                 %{transform: fn _ -> {:ok, "temp_file"} end},
                 :version,
                 %State{versions: %{version: %VersionState{}}}
               )

      assert {:error, :transform, "WAT!"} =
               Processor.transform_version(
                 %{transform: fn _ -> {:error, "WAT!"} end},
                 :version,
                 %State{versions: %{version: %VersionState{}}}
               )
    end
  end
end
