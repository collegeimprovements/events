defmodule OmGoogle.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/outermagic/om_google"

  def project do
    [
      app: :om_google,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Google API clients with service account authentication",
      package: package(),

      # Docs
      name: "OmGoogle",
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
      {:om_api_client, path: "../om_api_client"},
      {:fn_types, path: "../fn_types"},
      {:jose, "~> 1.11"},
      {:req, "~> 0.5"},
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
      main: "OmGoogle",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
