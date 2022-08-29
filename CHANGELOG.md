# Changelog

## 1.2.0

- Added CHANGELOG
- Add `Trunk.copy/4` to copy files between "folders" within the same file system (different directores in filesystem or different object keys in same S3 bucket)

## 1.2.1

- Return `nil` from `Trunk.filename/2` to prevent storing a specific version

## 1.3.0

- Returns `nil` from `url/1,2,3,4` if the `Trunk.filename/2` returns `nil`
