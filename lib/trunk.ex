defmodule Trunk do
  alias Trunk.State

  defmacro __using__(module_opts \\ []) do
    # IO.inspect(module_opts)

    quote location: :keep do
      @behaviour Trunk

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
        do: "#{rootname}_#{version}#{extname}"

      def storage_dir(state, version), do: ""

      def transform(state, version), do: nil

      defoverridable transform: 2, filename: 2, storage_dir: 2
    end
  end

  @doc ~S"""
  Generates the filename to be used for the specified version.

  - `state` - The trunk state
  - `version` - An atom representing the version

  Example:
  ```
  # For the :original version return the original file name
  def filename(%{filename: filename}, :original), do: filename
  # For any other version append the version to the root name
  #   mypic.jpg with :thumb version becomes mypic_thumb.jpg
  def filename(%{rootname: rootname, extname: extname}, version),
    do: "#{rootname}_#{version}#{extname}"
  ```
  """
  @callback filename(state :: Trunk.State.t, version :: atom) :: String.t

  @doc ~S"""
  Generates the storage directory in which to save the file

  Each storage system will have a base path in which to store files. The result of `storage_dir/2` is then appended to this to determine where to save files.

  - `state` - The trunk state
  - `version` - An atom representing the version

  Example:
  ```
  # Assuming a base path of /tmp files will be saved in /tmp
  def storage_dir(_state, _version), do: ""

  # Place the file in a directory named after a model id
  #  With a base path of /tmp and a scope of %{id: 42}, the file will be saved in /tmp/42/
  def storage_dir(%Trunk.State{scope: %{id: model_id}}, _version),
    do: to_string(model_id)
  ```
  """
  @callback storage_dir(state :: Trunk.State.t, version :: atom) :: String.t

  @type command :: atom | binary
  @type args :: String.t | [binary]
  @type ext :: atom
  @doc ~S"""
  Generate a transform instruction for a specific version.

  The transformation instruction is a command, arguments and an optional extension if the transformation will result in a file of a different extension from the supplied file (or to force a specific extension)

  ## Example:
  To generate a thumnail, you might have a version named `:thumb`.
  A transform that runs the uploaded file through ImageMagick’s `convert` could be the following
  ```
  def transform(%Trunk.State{}, :thumb),
    do: {:convert, "-strip -thumbnail 200x200>"}
  ```
  This would generate a call to `System.cmd` as follows:
  ```
  # input_file is the source (uploaded) file
  # output_file is a temporary file with the same extension as the source file
  System.cmd "convert", [input_file, "-strip", "-thumbnail", "200x200>", output_file], stderr_to_stdout: true
  ```

  To generate a JPEG thumbnail whether the source is JPEG or PNG you would add the extension to the transform instruction.
  ```
  def transform(%Trunk.State{}, :thumb),
    do: {:convert, "-strip -thumbnail 200x200>", :jpg}
  ```
  In this case the temporary file generated for the transformation would have a .jpg extension.
  """
  @callback transform(state :: Trunk.State.t, version :: atom) :: nil | {command, args} | {command, args, ext}
end
