defmodule OmQuery.MixProject do
  use Mix.Project

  def project do
    [
      app: :om_query,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11"},
      {:telemetry, "~> 1.0"},
      # Optional - for database integration
      {:postgrex, ">= 0.0.0", optional: true},
      # Optional - for JSON serialization
      {:jason, "~> 1.0", optional: true},
      # Dev/Test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
