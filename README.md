# Trunk

[![Build Status](https://travis-ci.org/andrewtimberlake/trunk.svg?branch=master)](https://travis-ci.org/andrewtimberlake/trunk)

**A file attachment/storage library for Elixir**

## Installation

Add `trunk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trunk, "~> 1.0"},

    # If you want to use Amazon S3, then add:
    {:ex_aws_s3, "~> 2.0"},
    {:hackney,   "~> 1.7"},
    {:poison,    "~> 3.1"},
    {:sweet_xml, "~> 0.6"},
  ]
end
```

Trunk has only one _hard_ dependency on [Briefly](https://hex.pm/packages/briefly) to handle temporary file creation (and auto-destruction)

## Usage

Trunk is a behaviour that is implemented in a module. `use Trunk` creates functions for storing, deleting, and generating urls for your files and their versions. It then implements callbacks in the simplest way possible. You can then override the callbacks you need to as you want to extend the behaviour.

```elixir
defmodule MyTrunk do
  use Trunk, versions: [:original, :thumb]

  # override callbacks as needed.
end
```

## Configuration

Trunk has been designed to be highly configurable. It can be configured in stages with each level merging with the level before it.

See the [documentation](https://hexdocs.pm/trunk/Trunk.html#module-options) for all config options.

### Global configuration

```elixir
config :trunk,
  storage: Trunk.Storage.Filesystem,
  storage_opts: [path: "/tmp"]
```

### App specific configuration for umbrella type configs

```elixir
config :my_app, :trunk,
  storage: Trunk.Storage.S3,
  storage_opts: [bucket: "test-trunk"]
```

in order for these options to be used, you need to pass the `otp_app` option when calling `use Trunk` as follows:

```elixir
defmodule MyTrunk do
  use Trunk, otp_app: :my_app
end
```

### Module configuration

```elixir
defmodule MyTrunk do
  use Trunk, versions: [:original, :trunk],
             storage: Trunk.Storage.Filesystem,
             storage_opts: [path: "/tmp"]
end
```

### Function options

**Caution:** If you override options during the storage call, you need to be sure to pass the same options to other calls

```elixir
MyTrunk.store("/path/to/file.ext", storage: Trunk.Storage.S3, storage_opts: [bucket: "test-trunk"])
```

## Storage

Storage is handled by a behaviour.

Two storage handlers are included: [Trunk.Storage.Filesystem](https://hexdocs.pm/trunk/Trunk.Storage.Filesystem.html), and [Trunk.Storage.S3](https://hexdocs.pm/trunk/Trunk.Storage.S3.html)
Additional storage systems can be handled by creating a module that implements the [Trunk.Storage](https://hexdocs.pm/trunk/Trunk.Storage.html) behaviour.

When storing files, Trunk runs the file through a transformation pipeline allowing you to generate different versions of a file.
Each stage in the pipeline is handled via a callback allowing you to configure what transformations take place, where the version is stored and how it is named.
Full information can be found [in the documentation](https://hexdocs.pm/trunk/Trunk.Storage.html#content)

## Scope

You have the option of passing a scope (usually a struct or map) into the transform functions. This scope object will then be available in each callback allowing you to further customise the handling of each version.

### Example:

```elixir
defmodule MyTrunk do
  use Trunk, versions: [:thumb]

  def storage_dir(%Trunk.State{scope: %{id: model_id}}, :thumb)
    do: "my_models/#{model_id}"
end

MyTrunk.store("/path/to/file.ext", %{id: 42})
# will save to <storage>/my_models/42/<filename>
```

## State

State about the file and the version transformations is kept in a [Trunk.State](https://hexdocs.pm/trunk/Trunk.State.html) struct which is passed to each callback. Each version also keeps track of its own state in a [Trunk.VersionState](https://hexdocs.pm/trunk/Trunk.VersionState.html) struct which is also available through the `Trunk.State.versions` map.

### Transformation

One of the key features of Trunk is the ability to take a file and produce transformed versions. Perhaps you want to take an uploaded photo and produce a thumbnail, take a video and extract thumbnails, or take an XLS file and produce a CSV file for easier processing.
This is all handled easily with the flexible version and transform system.

See full documentation on [Trunk.transform/2](https://hexdocs.pm/trunk/Trunk.html#c:transform/2)

## Credits

A shout out to [stavro](https://github.com/stavro) who created [arc](https://github.com/stavro/arc) which I used in many of my projects, and which provided much inspiration for what resulted in Trunk.

### Photos used in testing

- [coffee.jpg](https://unsplash.com/photos/Cdz_lvnl37k) by [Ronaldo Arthur Vidal](https://unsplash.com/@ronaldoav)
- [coffee beans.jpg](http://unsplash.com/photos/JS-QXqSGVE8) by [Alex Jones](https://unsplash.com/@alexjones)
