defmodule OmScheduler.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/outermagic/om_scheduler"

  def project do
    [
      app: :om_scheduler,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description: "A robust job scheduler with cron support, workflows, and pluggable backends",
      package: package(),
      docs: docs(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:ex_unit],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19", optional: true},
      {:decorator, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:dag, path: "../dag"},  # use path until hex published
      {:fn_types, path: "../fn_types"},  # use path until hex published
      {:fn_decorator, path: "../fn_decorator"},  # use path until hex published

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end

  defp package do
    [
      name: "om_scheduler",
      maintainers: ["Arpit"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "OmScheduler",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
