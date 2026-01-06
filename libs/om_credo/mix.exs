defmodule OmCredo.MixProject do
  use Mix.Project

  def project do
    [
      app: :om_credo,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Credo must be available at compile time for `use Credo.Check`
      {:credo, "~> 1.7", runtime: false}
    ]
  end
end
