defmodule OmHttp.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :om_http,
      version: @version,
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
      # No runtime dependencies - pure utility module
    ]
  end
end
