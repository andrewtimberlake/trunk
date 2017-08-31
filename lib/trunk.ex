defmodule Trunk do
  @moduledoc """
  A `Trunk` is a module used to handle the transformation and storage of files with multiple versions.

  ## Usage:
  To generate a `Trunk` call `use Trunk` and supply options to configure the specific behaviour you need.
  ```
  defmodule MyTrunk do
    use Trunk, versions: [:original],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: "/tmp"]
  end
  ```

  ## Options
  Options can be set at multiple levels
  - Global, use `config :trunk, key: :value`
  - Per otp app, use `config :my_app, trunk: [key: :value]`
  - Per module, supply options to `use Trunk`. Use `use Trunk, otp_app: :my_app` to read in per otp app options.
  - Per function, you can supply additional or override options to every function call.

  ### Available options
  - `:versions` a list of versions as atoms, `[:original, :thumb]`
  - `:async` (boolean) default `true`, whether to process each version in parallel or in sequence.
  - `:version_timeout` default `5_000`, how long to wait for each versions transformation and storage to complete when processing in parallel. **Note: ** if storing files non-locally (i.e. Amazon S3), then include both expected time for transformation and expected time for storage in this timeout.
  - `:storage` default `Trunk.Storage.Filesystem`, the storage module to use when storing files and versions
  - `:storage_opts` default: `[path: ""]`, the options for the storage module. See each storage module's documentation for available options.
  - `:otp_app`, only used at module level to read options specific to the otp app.

  ### Additional options
  Any extra options passed in at the otp app, module or function level are made available in the `opts` field of `Trunk.State`. This means that you can pass in any options you might need to use in any of the processing steps.

  ## File storage
  When files are stored, they are passed through a transformation pipeline which allows you to generate different versions of a file.
  You might get a photo uploaded which you want to save along with a thumbnail. You might have a video which also needs a thumbnail extracted. You could convert a spreadsheet to CSV or a document to PDF.

  At each point in the pipeline you have access to a `Trunk.State` or `Trunk.VersionState` struct which contains information collected at each step. Each state struct has an assigns map (similar to `Plug.Conn`) in which you can store information to be used later in the pipeline process or once storage is complete.

  The storage pipeline goes through the following steps:
  - `c:preprocess/1` - Here you have access to the information about the file including the path to the file on disk. This is where you can validate the file or extract information that can be useful for later processing. This callback is called only once for the pipeline.
  - `c:transform/2` - This is where you determine how each version should be transformed. You can return a transformation instruction or a function that will do the actual transformation. This callback is called once per version.
  - `c:postprocess/3` - Here you have access to information about the version after its transformation. At this point you have access to the state about the version including the path to the temporary file on disk. You can extract information about the version file like file size or hash its contents. This callback is called once per version.
  - `c:storage_dir/2` - This is where you determine at which path the version should be saved. This callback is called once per version.
  - `c:filename/2` - This is where you determine which filename the version should be saved as. This callback is called once per version.
  - `c:storage_opts/2` - This allows you to set additional storage options like file permissions `:acl` or add things like S3 headers (Check with the storage module as to what options are avialble to be set here). This callback is called once per version.
  - The file is saved using the configured storage module.

  ### Example:
  ```
  defmodule MyTrunk do
    use Trunk, versions: [:original, :thumb],
               storage: Trunk.Storage.Filesystem,
               storage_opts: [path: "/tmp"]

    # Ensure the file is a JPG or PNG file
    def preprocess(%Trunk.State{} = state) do
      if String.downcase(extname) in [".png", ".jpg", ".jpeg"] do
        {:ok, state}
      else
        {:error, "Invalid file"}
      end3
    end

    # Do not transform the original file
    def transform(%Trunk.State{}, :original), do: nil
    # Resize the file to a thumbnail of maximum 200x200px
    def transform(%Trunk.State{}, :thumb),
      do: {:convert, "-strip -thumbnail 200x200> -lmiit area 10MB -limit disk 100MB"}

    # Store the file size of each version
    def postprocess(%Trunk.VersionState{temp_path: temp_path} = version_state, _version, %Trunk.State{} = _state) do
      %File.State{size: file_size} = File.stat(temp_path)
      {:ok, Trunk.VersionState.assign(version_state, :file_size, file_size)}
    end

    # Store all versions in a directory based on a model id
    def storage_dir(%Trunk.State{scope: %{id: model_id}}, _version),
      do: to_string(model_id)

    # Store the original file with its original filename
    def filename(%Trunk.State{filename: filename}, :original),
      do: filename
    # Store other versions with the version in its filename
    def filename(%Trunk.State{rootname: rootname, extname: extname}, version),
      do: "\#{rootname}_\#{version}\#{extname}"

    def storage_opts(%Trunk.State{}, :original),
      do: [acl: 0o600]
    def storage_opts(%Trunk.State{}, :thumb),
      do: [acl: 0o644]
  end

  > {:ok, %Trunk.State{filename: filename, versions: versions}} = MyTrunk.store("/path/to/photo.jpg")
  > filename
  "photo.jpg"
  > versions |> Enum.map(fn({version, %Trunk.VersionState{assigns: %{file_size: file_size}}}) -> {version, file_size} end)
  [original: 34567, thumb: 456]
  ```
  """

  alias Trunk.State

  defmacro __using__(module_opts \\ []) do
    # IO.inspect(module_opts)

    quote location: :keep do
      @behaviour Trunk

      require Trunk
      import Trunk, only: [validate_file_extensions: 1]

      @impl true
      def store(file),
        do: store(file, nil, [])

      @impl true
      def store(file, [_ | _] = opts),
        do: store(file, nil, opts)
      def store(file, scope),
        do: store(file, scope, [])

      @impl true
      def store(file, [_ | _] = opts, []),
        do: store(file, nil, opts)
      def store(<<"http", _rest::binary>> = url, scope, opts) do
        filename = Path.basename(url)
        {:ok, 200, _headers, body} = :hackney.get(url, [], [], [with_body: true])
        store(%{filename: filename, binary: body}, scope, opts)
      end
      def store(file, scope, opts) when is_binary(file),
        do: store(%{filename: Path.basename(file), path: file}, scope, opts)
      def store(%{filename: filename, binary: binary}, scope, opts) do
        {:ok, path} = Briefly.create(extname: Path.extname(filename))
        File.write(path, binary, [:write, :binary])
        store(%{filename: filename, path: path}, scope, opts)
      end

      @impl true
      def store(%{filename: filename, path: path}, scope, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)

        with state <- State.init(%{filename: filename, path: path, module: __MODULE__}, scope, opts),
             {:ok, state} <- __MODULE__.preprocess(state) do
          Trunk.Processor.store(state)
        end
      end

      # def retrieve(file_info, scope \\ nil, version \\ :original, opts \\ [])
      @impl true
      def retrieve(file_info),
        do: retrieve(file_info, nil, :original, [])

      @impl true
      def retrieve(file_info, [_ | _] = opts),
        do: retrieve(file_info, nil, :original, opts)
      def retrieve(file_info, version) when is_atom(version),
        do: retrieve(file_info, nil, version, [])
      def retrieve(file_info, scope),
        do: retrieve(file_info, scope, :original, [])

      @impl true
      def retrieve(file_info, version, [_ | _] = opts) when is_atom(version),
        do: retrieve(file_info, nil, version, opts)
      def retrieve(file_info, scope, version) when is_atom(version),
        do: retrieve(file_info, scope, version, [])
      def retrieve(file_info, scope, [_ | _] = opts),
        do: retrieve(file_info, scope, :original, opts)

      @impl true
      def retrieve(nil, _scope, _version, _opts), do: nil
      def retrieve(<<filename::binary>>, scope, version, opts),
        do: retrieve(%{filename: filename}, scope, version, opts)
      def retrieve(%{} = file_info, scope, version, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)
        state = State.init(Map.merge(file_info, %{module: __MODULE__}), scope, opts)
        Trunk.Processor.retrieve(state, version)
      end

      @impl true
      def delete(file_info),
        do: delete(file_info, [])

      @impl true
      def delete(file_info, [_ | _] = opts),
        do: delete(file_info, nil, opts)
      def delete(file_info, scope),
        do: delete(file_info, scope, [])

      @impl true
      def delete(<<filename::binary>>, scope, opts),
        do: delete(%{filename: filename}, scope, opts)
      def delete(file_info, scope, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)
        state = State.init(Map.merge(file_info, %{module: __MODULE__}), scope, opts)
        Trunk.Processor.delete(state)
      end

      # def url(file_info, scope \\ nil, version \\ :original, opts \\ [])
      @impl true
      def url(file_info),
        do: url(file_info, nil, :original, [])

      @impl true
      def url(file_info, [_ | _] = opts),
        do: url(file_info, nil, :original, opts)
      def url(file_info, version) when is_atom(version),
        do: url(file_info, nil, version, [])
      def url(file_info, scope),
        do: url(file_info, scope, :original, [])

      @impl true
      def url(file_info, version, [_ | _] = opts) when is_atom(version),
        do: url(file_info, nil, version, opts)
      def url(file_info, scope, version) when is_atom(version),
        do: url(file_info, scope, version, [])
      def url(file_info, scope, [_ | _] = opts),
        do: url(file_info, scope, :original, opts)

      @impl true
      def url(nil, _scope, _version, _opts), do: nil
      def url(<<filename::binary>>, scope, version, opts),
        do: url(%{filename: filename}, scope, version, opts)
      def url(%{} = file_info, scope, version, opts) do
        opts = Trunk.Options.parse(unquote(module_opts), opts)
        state = State.init(Map.merge(file_info, %{module: __MODULE__}), scope, opts)

        Trunk.Processor.generate_url(state, version)
      end

      # Default implementations of callback functions
      @impl true
      def preprocess(state), do: {:ok, state}

      @impl true
      def postprocess(version_state, _version, _state), do: {:ok, version_state}

      @impl true
      def transform(_state, _version), do: nil

      @impl true
      def storage_dir(_state, _version), do: ""

      @impl true
      def filename(%{filename: filename}, :original), do: filename
      def filename(%{rootname: rootname, extname: extname}, version),
        do: "#{rootname}_#{version}#{extname}"

      @impl true
      def storage_opts(_state, _version), do: []

      defoverridable preprocess: 1, postprocess: 3, transform: 2, filename: 2, storage_dir: 2, storage_opts: 2
    end
  end

  @doc ~S"""
  A convenience macro for generating a `c:preprocess/1` function that validates the file being saved against a list of approved extensions (case-insensitive).

  ## Example:
  ```
  defmodule MyTrunk do
    use Trunk, versions: [:original]

    validate_file_extensions ~w[.jpg .jpeg .png]
  end
  ```
  """
  defmacro validate_file_extensions(extensions) do
    lower_extensions = Enum.map(Macro.expand(extensions, __CALLER__), &String.downcase/1)
    quote do
      @impl true
      def preprocess(%{lower_extname: extname} = state) do
        if extname in unquote(lower_extensions) do
          {:ok, state}
        else
          {:error, :invalid_file}
        end
      end
    end
  end

  @type scope :: map | struct
  @type opts :: Keyword.t
  @type version :: atom
  @type file :: String.t | Plug.Upload.t | %{filename: String.t, path: Path.t} | %{filename: String.t, binary: binary}
  @type file_info :: map | String.t

  @doc ~S"""
  A callback that can be used to do any preprocessing on the state before transformation and storage begins.

  This is a good place to do file validation (**Note** this example is wrapped in a convenience macro `validate_file_extensions/1`.
  ## Example
  ```
  def preprocess(%Trunk.State{lower_extname: extname} = state) do
    if extname in [".jpg", ".png"] do
      {:ok, state}
    else
      {:error, "Invalid file"}
    end
  end
  ```

  This is also a place to do any processing that might be needed when transforming versions.
  """
  @callback preprocess(state :: Trunk.State.t) :: {:ok, Trunk.State.t} | {:error, any}

  @doc ~S"""
  Stores the supplied file. **This function is generated by `use Trunk`**

  Calls `c:store/3` with `store(file, nil, [])`
  """
  @callback store(file) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Stores the supplied file. **This function is generated by `use Trunk`**

  Calls `c:store/3` with `store(file, nil, opts)`
  """
  @callback store(file, opts) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Stores the supplied file after running it through the processing pipeline. **This function is generated by `use Trunk`**

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
  Retrieves the original for the identified file. **This function is generated by `use Trunk`**

  Calls `c:retrieve/4` with `retrieve(file_info, nil, :original, [])`
  """
  @callback retrieve(file_info) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Retrieves the original, or specified version, for the identified file. **This function is generated by `use Trunk`**

  - With a `scope`, calls `c:retrieve/4` with `retrieve(file_info, scope, :original, [])`
  - With `opts`, calls `c:retrieve/4` with `retrieve(file_info, nil, :original, opts)`
  - With `version`, calls `c:retrieve/4` with `retrieve(file_info, nil, version, [])`
  """
  @callback retrieve(file_info, scope | opts | version) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Retrieves the original, or specified version, for the identified file. **This function is generated by `use Trunk`**

  - With a version and opts, calls `c:retrieve/4` with `retrieve(file_info, nil, version, opts)`
  - With a scope and version, calls `c:retrieve/4` with `retrieve(file_info, scope, version, [])`
  - With a scope and opts, calls `c:retrieve/4` with `retrieve(file_info, scope, :original, opts)`
  """
  @callback retrieve(file_info, scope | version, opts | version) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Retrieves the version for the identified file. **This function is generated by `use Trunk`**

  It returns an `{:ok, path}` tuple on success and `{:error, error}` tuple if an error occurred.

  - `file_info` - The file name or base info needed to identify the file. Minimum is `%{filename: "file.ext"}`
  - `scope` - (optional) a map or struct that will help when generating the filename and storage directory for saving the file
  - `version` - (optional) an atom representing the version
  - `opts` - (optional) options to override module, app, or global options. See "Options" in the module documentations for all options.
  """
  @callback retrieve(file_info, scope, version, opts) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Deletes the identified file and all its versions. **This function is generated by `use Trunk`**

  Calls `c:delete/3` with `delete(file_info, nil, [])`
  """
  @callback delete(file_info) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Deletes the identified file and all its versions. **This function is generated by `use Trunk`**

  - With a `scope`, calls `c:delete/3` with `delete(file_info, scope, [])`
  - With `opts`, calls `c:delete/3` with `delete(file_info, nil, opts)`
  """
  @callback delete(file_info, scope | opts) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Deletes the identified file and all its versions. **This function is generated by `use Trunk`**

  It returns an `{:ok, %Trunk.State{}}` tuple on success and `{:error, %Trunk.State{}}` tuple if an error occurred.

  - `file_info` - The file name or base info needed to identify the file. Minimum is `%{filename: "file.ext"}`
  - `scope` - (optional) a map or struct that will help when generating the filename and storage directory for saving the file
  - `opts` - (optional) options to override module, app, or global options. See "Options" in the module documentations for all options.
  """
  @callback delete(file_info, scope, opts) :: {:ok, Trunk.State.t} | {:error, Trunk.State.t}

  @doc ~S"""
  Generates a URL for the given information. **This function is generated by `use Trunk`**

  Calls `c:url/4` with `url(file_info, nil, :original, [])`
  """
  @callback url(file_info) :: String.t

  @doc ~S"""
  Generates a URL for the given information. **This function is generated by `use Trunk`**

  - With a `version`, calls `c:url/4` with `url(file_info, nil, version, [])`
  - With a `scope`, calls `c:url/4` with `url(file_info, scope, :original, [])`
  - With `opts`, calls `c:url/4` with `url(file_info, nil, :original, opts)`
  """
  @callback url(file_info, version | scope | opts) :: String.t

  @doc ~S"""
  Generates a URL for the given information. **This function is generated by `use Trunk`**

  - With a `version`, calls `c:url/4` with `url(file_info, nil, version, opts)`
  - With a `scope`, calls `c:url/4` with `url(file_info, scope, :original, opts)`
  """
  @callback url(file_info, version | scope, opts) :: String.t
  @doc ~S"""
  Generates a URL for the given information. **This function is generated by `use Trunk`**

  - `file_info` - The file name or base info needed to identify the file. Minimum is `%{filename: "file.ext"}`
  - `scope` - The scope object
  - `version` - The file version to which the URL must point
  - `opts` - Override options.
  """
  @callback url(file_info, scope, version, opts) :: String.t

  @doc ~S"""
  A callback that should be used to generate the filename specific to each version.

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
  @callback filename(state :: Trunk.State.t, version) :: String.t

  @doc ~S"""
  A callback that should be used to determine the storage directory specific to each version.

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
  @callback storage_dir(state :: Trunk.State.t, version) :: String.t

  @type storage_opts :: Keyword.t
  @doc ~S"""
  A callback that should be used to set version specific storage options.

  This is the place to set access permissions, storage headers (s3) and other options provided by the storage module.

  This callback should return a list of options.

  Example:
  ```
  # With Filesystem
  def storage_opts(_state, _version), do: [acl: "0600"]

  # With S3
  def storage_opts(_state, _version), do: [acl: :public_read]
  ```
  """
  @callback storage_opts(state :: Trunk.State.t, version) :: storage_opts

  @type command :: atom | binary
  @type args :: String.t | [binary] | function
  @type ext :: atom
  @type reason :: any
  @type transform_func :: ((source_path :: String.t) -> {:ok, String.t} | {:error, reason})
  @doc ~S"""
  A callback that can be used to generate a transform specific to each version

  The transformation instruction is a two element tuple `{command, arguments}`, a three element tuple `{command, arguments, extension}`, or a function that accepts a single argument (the source file path) and returns either `{:ok, "/path/to/transformed/file"}` or `{:error, "Reason"}`

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
  def transform(_state, :thumb),
    do: {:convert, "-strip -thumbnail 200x200>", :jpg}
  ```
  In this case the temporary file generated for the transformation would have a .jpg extension.

  In either form, the arguments can be generated by a function which receives the input and output file paths. This is useful for transforms where the input and output paths are not the first and last respectively.
  ```
  def transform(_state, _version),
    do: {:convert, fn(input, output) -> ["-density", "300", input, "-flatten", "-strip", "-thumbnail", "200x200>", output] end, :jpg}
  ```

  **Note:**  Returning an instruction with an extension will change the extension of the temporary file used in the transformation but will not affect the filename during save. That still needs to be done in `c:filename/2`

  Finally a function can be returned which will be wholly responsible for doing the transformation and returning the location of the transformed file.
  The function should return `{:ok, file_path}` if successful, or `{:error, reason}` if not.

  This example uses `soffice` to transform an XLS document to CSV. The problem is `soffice` doesn’t allow the output file to be specified so the above `{:soffice, [args]}` style can’t be used. To solve this, a transformation function is used to handle the transformation.
  The function creates a temporary directory for the transformation, runs the `soffice` command and then parses the output for the resulting file.
  ```
  def transform(%Trunk.State{extname: extname}, :csv) when extname in [".xls", ".xlsx"],
    do: fn(source_path) ->
          {:ok, directory} = Briefly.create(directory: true)
          # soffice must be in the PATH
          case System.cmd("soffice", ["--headless", "--convert-to", "csv:Text - txt - csv (StarCalc):44,34,76,0", "--outdir", directory, source_path], stderr_to_stdout: true) do
            {output, 0} ->
              [_, path] = Regex.run(~r/-> (.+\.csv)/, output)
              {:ok, path}
            {result, _} -> {:error, result}
          end
        end
  def transform(_state, _version), do: nil
  ```
  """
  @callback transform(state :: Trunk.State.t, version) :: nil | {command, args} | {command, args, ext} | transform_func

  @doc ~S"""
  A callback that can be used to do additional processing on each version file before it gets saved.

  This callback can update the version state information which can then be used in `storage_dir/2` and `filename/2` as additional information for storage.

  **Note: ** If information is stored in the version state and used for file naming, then that information needs to be stored in order to retrieve that file or generate a URL etc.

  ## Example:
  To generate and store the md5 hash of each version.
  ```
  def postprocess(%Trunk.VersionState{temp_path: temp_path} = version_state, _version, _state) do
    hash = :crypto.hash(:md5, File.read!(temp_path)) |> Base.encode16(case: :lower)
    {:ok, Trunk.VersionState.assign(version_state, :hash, hash)}
  end
  ```

  ## Example:
  To calculate and store the file size of each version.
  ```
  def postprocess(%Trunk.VersionState{temp_path: temp_path} = version_state, _version, _state) do
    {:ok, %File.Stat{size: file_size}} = File.stat(temp_path)
    {:ok, Trunk.VersionState.assign(version_state, :file_size, file_size)}
  end
  ```
  """
  @callback postprocess(version_state :: Trunk.VersionState.t, version, state :: Trunk.State.t) :: {:ok, Trunk.VersionState.t} | {:error, any}
end
