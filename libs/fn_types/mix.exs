defmodule FnTypes.MixProject do
  use Mix.Project

  def project do
    [
      app: :fn_types,
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
      # Optional - for Ecto/Postgrex protocol implementations
      {:ecto, "~> 3.11", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      # Dev/Test
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
