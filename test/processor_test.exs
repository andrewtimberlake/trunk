defmodule Trunk.ProcessorTest do
  use ExUnit.Case, async: true

  alias Trunk.{Processor, State, VersionState}

  describe "transformations" do
    defmodule TestTrunk do
      use Trunk, versions: []

      def transform(_state, :timeout_version),
        do: fn(_) -> Process.sleep(2_000) end
    end

    test "version timeout" do
      assert {:error, %{errors: errors}} = Processor.store(%State{module: TestTrunk, versions: %{timeout_version: %VersionState{}}, version_timeout: 500})
      assert %{timeout_version: [processing: :timeout]} = errors
    end
  end
end
