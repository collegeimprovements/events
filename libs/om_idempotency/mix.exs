defmodule OmIdempotency.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourusername/om_idempotency"

  def project do
    [
      app: :om_idempotency,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Database-backed idempotency key management for safe API retries",
      package: package(),

      # Docs
      name: "OmIdempotency",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11"},
      {:telemetry, "~> 1.0"},

      # Optional deps
      {:req, "~> 0.4", optional: true},

      # Dev/Test
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
      main: "OmIdempotency",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
