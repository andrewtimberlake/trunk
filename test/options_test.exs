defmodule Trunk.OptionsTest do
  use ExUnit.Case, async: false # Modifying global state with options

  alias Trunk.Options

  test "default options" do
    options = Options.parse([], [])
    assert length(options) == 5
    assert Keyword.get(options, :async) == true
    assert Keyword.get(options, :versions) == [:original]
    assert Keyword.get(options, :timeout) == 5_000
    assert Keyword.get(options, :storage) == Trunk.Storage.Filesystem
    assert Keyword.get(options, :storage_opts) == [path: ""]
  end

  describe "global options" do
    setup do
      Application.put_env(:trunk, :async, false)
      Application.put_env(:trunk, :timeout, 10_000)

      on_exit(fn ->
        Application.delete_env(:trunk, :async)
        Application.delete_env(:trunk, :timeout)
      end)
    end

    test "global options override defaults" do
      options = Options.parse([], [])
      assert Keyword.get(options, :async) == false
      assert Keyword.get(options, :timeout) == 10_000
    end
  end

  describe "otp app options" do
    setup do
      Application.put_env(:trunk, :async, false)
      Application.put_env(:trunk, :timeout, 10_000)
      Application.put_env(:test_app, :trunk, async: false, timeout: 15_000)

      on_exit(fn ->
        Application.delete_env(:trunk, :async)
        Application.delete_env(:trunk, :timeout)
        Application.delete_env(:test_app, :trunk)
      end)
    end

    test "otp app options override defaults and globals" do
      options = Options.parse([otp_app: :test_app], [])
      assert Keyword.get(options, :async) == false
      assert Keyword.get(options, :timeout) == 15_000
    end
  end

  describe "module options" do
    setup do
      Application.put_env(:trunk, :timeout, 10_000)
      Application.put_env(:test_app, :trunk, async: false, timeout: 15_000)

      on_exit(fn ->
        Application.delete_env(:trunk, :timeout)
        Application.delete_env(:test_app, :trunk)
      end)
    end

    test "module options override defaults and global" do
      options = Options.parse([timeout: 20_000], [])
      assert Keyword.get(options, :timeout) == 20_000
    end

    test "module options override defaults, global and otp app" do
      options = Options.parse([otp_app: :test_app, timeout: 20_000], [])
      assert Keyword.get(options, :timeout) == 20_000
    end
  end

  describe "method options" do
    setup do
      Application.put_env(:trunk, :timeout, 10_000)
      Application.put_env(:trunk, :storage_opts, [bucket: "my-bucket"])
      Application.put_env(:test_app, :trunk, async: false, timeout: 15_000)

      on_exit(fn ->
        Application.delete_env(:trunk, :timeout)
        Application.delete_env(:trunk, :storage_opts)
        Application.delete_env(:test_app, :trunk)
      end)
    end

    test "method options override defaults and global" do
      options = Options.parse([timeout: 20_000], [timeout: 25_000, storage_opts: [signed: true]])
      assert Keyword.get(options, :timeout) == 25_000
      assert Keyword.get(options, :storage_opts) == [path: "", bucket: "my-bucket", signed: true]
    end

    test "module options override defaults, global and otp app" do
      options = Options.parse([otp_app: :test_app, timeout: 20_000], [timeout: 25_000])
      assert Keyword.get(options, :timeout) == 25_000
    end
  end

  describe "alias version_timeout" do
    test ":verstion_timeout generates a warning" do
      warning = ExUnit.CaptureIO.capture_io(:stderr, fn ->
        options = Options.parse([version_timeout: 12_000], [])
        assert options[:timeout] == 5_000
        refute options[:verstion_timeout]
      end)
      assert warning =~ ~r/option :version_timeout is deprecated, use :timeout/
    end
  end
end
