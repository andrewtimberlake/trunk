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
      def store(<<"http", _rest::binary>> = url, scope, opts) do
        filename = Path.basename(url)
        {:ok, 200, _headers, ref} = :hackney.get(url, [], [], [])
        {:ok, body} = :hackney.body(ref)
        store(%{filename: filename, binary: body}, scope, opts)
      end
      def store(file, scope, opts) when is_binary(file),
        do: store(%{filename: Path.basename(file), path: file}, scope, opts)
      def store(%{filename: filename, binary: binary}, scope, opts) do
        {:ok, path} = Briefly.create(extname: Path.extname(filename))
        File.write(path, binary, [:write, :binary])
        store(%{filename: filename, path: path}, scope, opts)
      end
      def store(%{filename: filename, path: path}, scope, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)

        with state <- State.init(%{filename: filename, path: path, module: __MODULE__}, scope, opts),
             {:ok, state} <- __MODULE__.preprocess(state) do
          Trunk.Processor.store(state)
        end
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

      # Default implementations of callback functions
      def preprocess(state), do: {:ok, state}

      def filename(%{filename: filename}, :original), do: filename
      def filename(%{rootname: rootname, extname: extname}, version),
        do: "#{rootname}_#{version}#{extname}"

      def storage_dir(state, version), do: ""

      def transform(state, version), do: nil

      defoverridable preprocess: 1, transform: 2, filename: 2, storage_dir: 2
    end
  end

  @type scope :: map | struct
  @type opts :: Keyword.t
  @type version :: atom
  @type file :: String.t | Plug.Upload.t | %{filename: String.t, path: Path.t} | %{filename: String.t, binary: binary}

  @doc ~S"""
  A callback to do any preprocessing on the state before transformation and storage begins.

  This is a good place to do file validation.
  ## Example
  ```
  def preprocess(%Trunk.State{extname: extname} = state) do
    if String.downcase(extname) in [".jpg", ".png"] do
      {:ok, state}
    else
      {:error, "Invalid file"}
    end
  end
  ```

  This is also a place to do any processing that might be needed when transforming versions.
  """
  @callback preprocess(Trunk.State.t) :: {:ok, Trunk.State.t} | {:error, any}

  @doc ~S"""
  Stores the supplied file.

  Calls `c:store/3` with `store(file, nil, [])`
  """
  @callback store(file) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Stores the supplied file.

  Calls `c:store/3` with `store(file, nil, opts)`
  """
  @callback store(file, opts) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Stores the supplied file after running it through the processing pipeline.

  It returns an `{:ok, %Trunk.State{}}` tuple on success and `{:error, %Trunk.State{}}` tuple if an error occurred anywhere in the processing pipeline.

  - `file` - the file to store.
    - This can be a full path to file, or
    - a url to a file, or
    - a map with `:filename` and `:path` keys (e.g. `%Plug.Upload{}`), or
    - a map with `:filename` and `:binary` keys (e.g. `%{filename: "myfile.jpg", binary: <<…>>}`)
  - `scope` - (optional) a map or struct that will help when generating the filename and storage directory for saving the file
  - `opts` - (optional) options to override module, app, or global options. See "Options" in the module documentations for all options.
  """
  @callback store(file, scope, opts) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Generates a URL for the given information.

  Calls `c:url/4` with `url(info, nil, :original, [])`
  """
  @callback url(info :: map) :: String.t

  @doc ~S"""
  Generates a URL for the given information.

  Calls `c:url/4` with `url(info, nil, :original, opts)`
  """
  @callback url(info :: map, opts) :: String.t

  @doc ~S"""
  Generates a URL for the given information.

  - With a `version`, calls `c:url/4` with `url(info, nil, version, [])`
  - With a `scope`, calls `c:url/4` with `url(info, scope, :original, [])`
  """
  @callback url(info :: map, version | scope) :: String.t

  @doc ~S"""
  Generates a URL for the given information.

  - With a `version`, calls `c:url/4` with `url(info, nil, version, opts)`
  - With a `scope`, calls `c:url/4` with `url(info, scope, :original, opts)`
  """
  @callback url(info :: map, version | scope, opts) :: String.t
  @doc ~S"""
  Generates a URL for the given information.
  - `info` - The base info needed to identify the file. Minimum is `%{filename: "file.ext"}`
  - `scope` - The scope object
  - `version` - The file version to which the URL must point
  - `opts` - Override options.
  """
  @callback url(info :: map, scope, version, opts) :: String.t

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

  ## Note:
  Returning an instruction with an extension will change the extension of the temporary file used in the transformation but will not affect the filename during save. That still needs to be done in `c:filename/2`
  """
  @callback transform(state :: Trunk.State.t, version :: atom) :: nil | {command, args} | {command, args, ext}
end
