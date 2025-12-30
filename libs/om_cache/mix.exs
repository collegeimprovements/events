defmodule OmCache.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/anthropics/om_cache"

  def project do
    [
      app: :om_cache,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Nebulex cache wrapper with adapter selection, key generation, and graceful degradation",
      package: package(),

      # Docs
      name: "OmCache",
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
      {:nebulex, "~> 2.6"},
      {:nebulex_redis_adapter, "~> 2.4"},
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
      main: "OmCache",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
