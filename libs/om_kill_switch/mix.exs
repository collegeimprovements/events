defmodule OmKillSwitch.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/outermagic/om_kill_switch"

  def project do
    [
      app: :om_kill_switch,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Runtime service kill switch for graceful degradation",
      package: package(),

      # Docs
      name: "OmKillSwitch",
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
      {:telemetry, "~> 1.0"},
      # Optional service integrations
      {:om_s3, path: "../om_s3", optional: true},
      {:om_cache, path: "../om_cache", optional: true},
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
      main: "OmKillSwitch",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
