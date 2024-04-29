defmodule Trunk.Mixfile do
  use Mix.Project

  @github_url "https://github.com/andrewtimberlake/trunk"
  @version "1.4.0"

  def project do
    [
      app: :trunk,
      version: @version,
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp package do
    [
      description: "A file attachment/storage library for Elixir",
      maintainers: ["Andrew Timberlake"],
      licenses: ["MIT"],
      links: %{"GitHub" => @github_url}
    ]
  end

  def docs do
    [
      extras: [
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"],
        "USAGE.md": [title: "Usage"],
        "CHANGELOG.md": [title: "Change Log"]
      ],
      main: "readme",
      source_url: @github_url,
      source_ref: @version,
      formatters: ["html"]
    ]
  end

  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:briefly, "~> 0.4.0 or ~> 0.5.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_aws_s3, "~> 2.0", optional: true},
      {:hackney, ">= 1.7.0", optional: true},
      {:jason, ">= 1.0.0", optional: true},
      {:sweet_xml, "~> 0.6", optional: true},
      {:bypass, "~> 2.0", only: :test},
      {:credo, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
