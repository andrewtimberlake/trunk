opts = if System.get_env("TRUNK_TEST_S3_ACCESS_KEY"), do: [], else: [exclude: [:s3]]
ExUnit.configure opts
ExUnit.start()
