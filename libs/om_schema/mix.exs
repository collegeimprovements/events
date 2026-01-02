defmodule OmSchema.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/outermagic/om_schema"
  @description "Enhanced Ecto schema macros, presets, and validations."

  def project do
    [
      app: :om_schema,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      name: "OmSchema",
      docs: docs(),
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
      {:telemetry, "~> 1.0"},
      # Optional - for database validation
      {:ecto_sql, "~> 3.11", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      # Dev/Test
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
      main: "OmSchema",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
