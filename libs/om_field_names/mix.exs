defmodule OmFieldNames.MixProject do
  use Mix.Project

  def project do
    [
      app: :om_field_names,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # No dependencies - pure Elixir
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
