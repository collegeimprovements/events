defmodule OmApiClient.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourusername/om_api_client"

  def project do
    [
      app: :om_api_client,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "HTTP API client framework with middleware, retry, circuit breaker, and rate limiting",
      package: package(),

      # Docs
      name: "OmApiClient",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:telemetry, "~> 1.0"},
      {:fn_types, path: "../fn_types"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "OmApiClient",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
