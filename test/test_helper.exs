opts = if System.get_env("TRUNK_TEST_S3_ACCESS_KEY"), do: [], else: [exclude: [:s3]]
ExUnit.configure(opts)
Application.ensure_all_started(:hackney)
ExUnit.start()
