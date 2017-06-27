defmodule Trunk.StateTest do
  use ExUnit.Case, async: true

  alias Trunk.{State, VersionState}

  test "put_error/4" do
    state = State.put_error(%State{}, :thumb, :transform, "Invalid option")
    assert %{errors: %{thumb: [transform: "Invalid option"]}} = state
  end

  test "assign/3" do
    state = State.assign(%State{}, :my_key, :my_value)
    assert state.assigns[:my_key] == :my_value
  end

  describe "save/2" do
    test "saves the filename by default" do
      state = %State{filename: "test.jpg"}
      assert State.save(state) == "test.jpg"
    end

    test "saves the filename" do
      state = %State{filename: "test.jpg"}
      assert State.save(state, as: :string) == "test.jpg"
    end

    test "raise error if attempting to save as string with assigns" do
      state = %State{filename: "test.jpg", assigns: %{hash: "abcdef"}}
      assert_raise ArgumentError, fn ->
        State.save(state, as: :string)
      end

      state = %State{filename: "test.jpg", versions: %{original: %{assigns: %{hash: "abcdef"}}}}
      assert_raise ArgumentError, fn ->
        State.save(state, as: :string)
      end
    end

    test "do not raise error if attempting to save as string with assigns and ignore_assigns is set" do
      state = %State{filename: "test.jpg", assigns: %{file_size: 12345}}
      assert State.save(state, as: :string, ignore_assigns: true) == "test.jpg"

      state = %State{filename: "test.jpg", versions: %{original: %{assigns: %{file_size: 12345}}}}
      assert State.save(state, as: :string, ignore_assigns: true) == "test.jpg"
    end

    test "saves a full hash with all assigns" do
      state = %State{filename: "test.jpg", assigns: %{hash: "abcdef"}, versions: %{original: %VersionState{assigns: %{hash: "fedcba"}}, thumb: %VersionState{assigns: %{hash: "abcdfe"}}}}
      assert State.save(state, as: :map) == %{filename: "test.jpg", assigns: %{hash: "abcdef"}, version_assigns: %{original: %{hash: "fedcba"}, thumb: %{hash: "abcdfe"}}}
    end

    test "saves a full hash with only required assigns" do
      state = %State{filename: "test.jpg", assigns: %{hash: "abcdef", file_size: 1234}, versions: %{original: %VersionState{assigns: %{hash: "fedcba", file_size: 1234}}, thumb: %VersionState{assigns: %{hash: "abcdfe", file_size: 123}}}}
      assert State.save(state, as: :map, assigns: [:hash]) == %{filename: "test.jpg", assigns: %{hash: "abcdef"}, version_assigns: %{original: %{hash: "fedcba"}, thumb: %{hash: "abcdfe"}}}
    end

    test "saves a full hash with all assigns as json" do
      state = %State{filename: "test.jpg", assigns: %{hash: "abcdef"}, versions: %{original: %VersionState{assigns: %{hash: "fedcba"}}, thumb: %VersionState{assigns: %{hash: "abcdfe"}}}}
      assert Poison.decode!(State.save(state, as: :json)) == Poison.decode!(~S({"filename":"test.jpg","assigns":{"hash":"abcdef"},"version_assigns":{"thumb":{"hash":"abcdfe"},"original":{"hash":"fedcba"}}}))
    end
  end

  describe "restore/2" do
    test "restores from a filename" do
      assert %State{filename: "my_file.ext"} = State.restore("my_file.ext")
    end

    test "restores from a map" do
      assert %State{filename: "my_file.ext",
                    assigns: %{hash: "abcdef"},
                    versions: %{original: %VersionState{assigns: %{hash: "fedcba"}},
                                thumb: %VersionState{assigns: %{hash: "abcdfe"}}}} =
        State.restore(%{filename: "my_file.ext", assigns: %{hash: "abcdef"},
                        version_assigns: %{
                           original: %{hash: "fedcba"},
                           thumb: %{hash: "abcdfe"}}})
    end

    test "restores from a map with string keys" do
      assert %State{filename: "my_file.ext",
                    assigns: %{hash: "abcdef"},
                    versions: %{original: %VersionState{assigns: %{hash: "fedcba"}},
                                thumb: %VersionState{assigns: %{hash: "abcdfe"}}}} =
        State.restore(%{"filename" => "my_file.ext", "assigns" => %{"hash" => "abcdef"},
                        "version_assigns" => %{
                          "original" => %{"hash" => "fedcba"},
                          "thumb" => %{"hash" => "abcdfe"}}})
    end

    test "restores from a json string" do
      json = ~S({"filename":"my_file.ext","assigns":{"hash":"abcdef"},"version_assigns":{"thumb":{"hash":"abcdfe"},"original":{"hash":"fedcba"}}})
      assert %State{filename: "my_file.ext",
                    assigns: %{hash: "abcdef"},
                    versions: %{original: %VersionState{assigns: %{hash: "fedcba"}},
                                thumb: %VersionState{assigns: %{hash: "abcdfe"}}}} =
        State.restore(json)
    end
  end
end
