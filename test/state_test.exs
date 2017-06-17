defmodule Trunk.StateTest do
  use ExUnit.Case, async: true

  alias Trunk.State

  test "put_error/4" do
    state = State.put_error(%State{}, :thumb, :transform, "Invalid option")
    assert %{errors: %{thumb: {:transform, "Invalid option"}}}
  end
end
