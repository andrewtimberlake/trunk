defmodule Trunk.Mixfile do
  use Mix.Project

  @github_url "https://github.com/andrewtimberlake/trunk"

  def project do
    [
      app: :trunk,
      version: "0.0.4",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      description: "A file attachment/storage library for Elixir",
      package: package(),
      deps: deps(),
      docs: docs(),
    ]
  end

  defp package do
    [
      maintainers: ["Andrew Timberlake"],
      licenses: ["MIT"],
      links: %{"GitHub" => @github_url},
    ]
  end

  def docs do
    [
      source_url: @github_url,
      extras: ["EXAMPLES.md"]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:briefly, "~> 0.3.0"},

      {:ex_doc, ">= 0.0.0", only: :dev},
      {:ex_aws, "~> 1.1", only: [:dev, :test]},
      {:hackney, "~> 1.7", only: [:dev, :test]},
      {:poison, "~> 3.1", only: [:dev, :test]},
      {:sweet_xml, "~> 0.6", only: [:dev, :test]},
      {:bypass, "~> 0.6", only: :test},
      {:credo, "~> 0.8", only: [:dev, :test]},
    ]
  end
end
