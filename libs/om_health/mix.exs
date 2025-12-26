defmodule OmHealth.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourorg/om_health"

  def project do
    [
      app: :om_health,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: "System health monitoring and status reporting framework"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:fn_types, path: "../fn_types"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "OmHealth",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
