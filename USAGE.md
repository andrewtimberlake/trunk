# Examples

## Simple Example

This example does nothing but implement Trunk and override the `c:Trunk.transform/2` callback for the `:thumbnail` version

```elixir
defmodule MyTrunk do
  use Trunk, versions: [:original, :thumbnail]

  def transform(_state, :thumbnail),
    do: {:convert, "-strip -thumbnail 100x100>"}
  def transform(state, version), do: super(state, version)
end

{:ok, _state} = MyTrunk.store("/path/to/picture.jpg")
# Will store original in <storage>/picture.jpg
#        and thumbnail in <storage>/picture_thumbnail.jpg
```

## Full Example

This example simply shows a full implementation with all the callback functions overridden.

```elixir
defmodule MyTrunk do
  use Trunk, versions: [:original, :thumbnail],
             storage: Trunk.Storage.S3,
             storage_opts: [bucket: "my-bucket",
                            ex_aws: [acl: :public_read]]

  def preprocess(%Trunk.State{lower_extname: extname} = state) do
    if extname in [".png", ".jpg", ".jpeg"] do
      {:ok, state}
    else
      {:error, "Invalid file"}
    end
  end

  def transform(_state, :thumbnail),
    do: {:convert, "-strip -thumbnail 100x100>", :jpg}
  def transform(_state, :original), do: nil

  def postprocess(%Trunk.VersionState{temp_path: temp_path} = version_state, :thumbnail, _state) do
    hash = :crypto.hash(:md5, File.read!(temp_path)) |> Base.encode16(case: :lower)
    {:ok, Trunk.VersionState.assign(version_state, :hash, hash)}
  end
  def postprocess(version_state, version, state), do: super(version_state, version, state)

  def storage_opts(_state, :original),
    do: [acl: :private]
  def storage_opts(_state, :thumbnail),
    do: [acl: :private, content_type: "image/jpeg"]

  def storage_dir(%Trunk.State{scope: %MyModel{id: model_id}}, _version),
    do: "photos/#{model_id}"

  def filename(state, :thumbnail),
    do: "thumbnail_#{Trunk.State.get_version_assign(state, :thumbnail, :hash)}.jpg"
  def filename(%Trunk.State{filename: filename}, :original), do: filename
end

iex> my_model = %MyModel{id: 42}
iex> {:ok, state} = MyTrunk.store("/path/to/picture.png", my_model)
# Will store original in s3://my-bucket/photos/42/picture.png
#        and thumbnail in s3://my-bucket/photos/42/thumbnail_889c00fed0f5382b4bdea612ae7a42df.jpg

iex> %{my_model | file: Trunk.State.save(state, as: :map)}
%MyModel{id: 42, file: %{filename: "picture.png", version_assigns: %{thumbnail: %{hash: "889c00fed0f5382b4bdea612ae7a42df"}}}}

iex> {:error, "Invalid file"} = MyTrunk.store("/path/to/document.pdf", my_model)
```