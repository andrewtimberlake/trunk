defmodule Trunk.VersionStateTest do
  use ExUnit.Case, async: true

  alias Trunk.VersionState

  test "assign/3" do
    version_state = VersionState.assign(%VersionState{}, :my_key, :my_value)
    assert version_state.assigns[:my_key] == :my_value
  end
end
