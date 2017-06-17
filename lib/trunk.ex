defmodule Trunk do
  alias Trunk.State

  defmacro __using__(module_opts \\ []) do
    # IO.inspect(module_opts)

    quote location: :keep do
      @doc ~S"""
      This is the doc for store
      """
      def store(file, scope \\ nil, opts \\ [])
      def store(file, [_ | _] = opts, []),
        do: store(file, nil, opts)
      def store(file, scope, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)
        filename = Path.basename(file)
        state = State.init(%{file: file, filename: filename, module: __MODULE__}, scope, opts)

        Trunk.Processor.save(state)
      end

      # def url(info, scope \\ nil, version \\ :original, opts \\ [])
      def url(info),
        do: url(info, nil, :original, [])

      def url(info, [_ | _] = opts),
        do: url(info, nil, :original, opts)
      def url(info, version) when is_atom(version),
        do: url(info, nil, version, [])
      def url(info, state),
        do: url(info, state, :original, [])

      def url(info, version, [_ | _] = opts) when is_atom(version),
        do: url(info, nil, version, opts)
      def url(info, state, [_ | _] = opts),
        do: url(info, state, :original, opts)

      def url(<<filename::binary>>, scope, version, opts),
        do: url(%{filename: filename}, scope, version, opts)
      def url(%{} = info, scope, version, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)
        state = State.init(Map.merge(info, %{module: __MODULE__}), scope, opts)

        Trunk.Processor.generate_url(state, version)
      end

      def filename(%{filename: filename}, :original), do: filename
      def filename(%{rootname: rootname, extname: extname}, version),
        do: rootname <> "_" <> to_string(version) <> extname

      def storage_dir(state, version), do: ""

      def transform(state, version), do: nil

      defoverridable transform: 2, filename: 2, storage_dir: 2
    end
  end
end
