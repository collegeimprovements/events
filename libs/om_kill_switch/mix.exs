defmodule OmKillSwitch.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourusername/om_kill_switch"

  def project do
    [
      app: :om_kill_switch,
      version: @version,
      elixir: "~> 1.14",
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
      main: "OmKillSwitch",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
