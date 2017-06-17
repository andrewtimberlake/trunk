defmodule Trunk.Options do
  def parse(module_opts, method_opts) do
    defaults = [
      versions: [:original],
      async: true,
      version_timeout: 5_000,
      storage: Trunk.Storage.Filesystem,
      storage_opts: [path: ""],
    ]

    defaults
    |> Keyword.merge(Application.get_all_env(:trunk))
    |> merge_otp_app_opts(module_opts)
    |> Keyword.merge(module_opts)
    |> Keyword.merge(method_opts)
    |> filter_options
  end

  defp merge_otp_app_opts(opts, module_opts) do
    otp_app = Keyword.get(module_opts, :otp_app, [])
    otp_opts = Application.get_env(otp_app, :trunk, [])
    Keyword.merge(opts, otp_opts)
  end

  defp filter_options(opts, acc \\ [])
  defp filter_options([], acc), do: acc
  defp filter_options([{:async, async} | tail], acc),
    do: filter_options(tail, [{:async, async} | acc])
  defp filter_options([{:path, path} | tail], acc),
    do: filter_options(tail, [{:path, path} | acc])
  defp filter_options([{:storage, storage} | tail], acc),
    do: filter_options(tail, [{:storage, storage} | acc])
  defp filter_options([{:storage_opts, storage_opts} | tail], acc),
    do: filter_options(tail, [{:storage_opts, storage_opts} | acc])
  defp filter_options([{:versions, versions} | tail], acc),
    do: filter_options(tail, [{:versions, versions} | acc])
  defp filter_options([{:version_timeout, version_timeout} | tail], acc),
    do: filter_options(tail, [{:version_timeout, version_timeout} | acc])
  defp filter_options([_head | tail], acc),
    do: filter_options(tail, acc)
end
