defmodule Effect.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :effect,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Effect",
      description: "Composable, resumable workflow orchestration for Elixir",
      dialyzer: [plt_add_apps: [:ex_unit]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Required - internal dependencies
      {:dag, path: "../dag"},
      {:fn_types, path: "../fn_types"},

      # Optional - observability
      {:telemetry, "~> 1.0", optional: true},
      {:opentelemetry_api, "~> 1.0", optional: true},

      # Dev/Test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end
end
