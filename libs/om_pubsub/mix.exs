defmodule OmPubSub.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/anthropics/om_pubsub"

  def project do
    [
      app: :om_pubsub,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Phoenix.PubSub wrapper with Redis, PostgreSQL, and local adapters",
      package: package(),

      # Docs
      name: "OmPubSub",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_pubsub_redis, "~> 3.0"},
      {:postgrex, "~> 0.17"},
      {:redix, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:fn_types, path: "../fn_types"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Arpit"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "OmPubSub",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
