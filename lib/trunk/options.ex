defmodule Trunk.Options do
  @moduledoc false

  def parse(module_opts, method_opts) do
    defaults = [
      versions: [:original],
      async: true,
      timeout: 5_000,
      storage: Trunk.Storage.Filesystem,
      storage_opts: [path: ""]
    ]

    defaults
    |> Keyword.merge(Application.get_all_env(:trunk), &merge_values/3)
    # Application.get_all_env will return every config for the :trunk app
    |> filter_options
    #  so we filter it for only the ones we need.
    |> merge_otp_app_opts(module_opts)
    |> Keyword.merge(module_opts, &merge_values/3)
    |> Keyword.merge(method_opts, &merge_values/3)
    |> process_deprecations
  end

  defp process_deprecations(keyword_lsit, acc \\ [])
  defp process_deprecations([], acc), do: acc

  defp process_deprecations([{:version_timeout, _value} | _tail], acc) do
    IO.warn("option :version_timeout is deprecated, use :timeout")
    acc
  end

  defp process_deprecations([head | tail], acc), do: process_deprecations(tail, [head | acc])

  defp merge_otp_app_opts(opts, module_opts) do
    otp_app = Keyword.get(module_opts, :otp_app, nil)
    otp_opts = if otp_app, do: Application.get_env(otp_app, :trunk, []), else: []
    Keyword.merge(opts, otp_opts, &merge_values/3)
  end

  defp merge_values(key, val1, val2)

  defp merge_values(_key, [{key1, _} | _] = list1, [{key2, _} | _] = list2)
       when is_atom(key1) and is_atom(key2),
       do: Keyword.merge(list1, list2, &merge_values/3)

  defp merge_values(_key, [{key1, _val} | _tail] = list1, []) when is_atom(key1), do: list1
  defp merge_values(_key, _arg1, arg2), do: arg2

  defp filter_options(opts, acc \\ [])
  defp filter_options([], acc), do: acc

  defp filter_options([{:async, async} | tail], acc),
    do: filter_options(tail, [{:async, async} | acc])

  defp filter_options([{:storage, storage} | tail], acc),
    do: filter_options(tail, [{:storage, storage} | acc])

  defp filter_options([{:storage_opts, storage_opts} | tail], acc),
    do: filter_options(tail, [{:storage_opts, storage_opts} | acc])

  defp filter_options([{:versions, versions} | tail], acc),
    do: filter_options(tail, [{:versions, versions} | acc])

  defp filter_options([{:version_timeout, timeout} | tail], acc),
    do: filter_options(tail, [{:version_timeout, timeout} | acc])

  defp filter_options([{:timeout, timeout} | tail], acc),
    do: filter_options(tail, [{:timeout, timeout} | acc])

  defp filter_options([_head | tail], acc), do: filter_options(tail, acc)
end
