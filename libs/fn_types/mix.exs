defmodule FnTypes.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourusername/fn_types"

  def project do
    [
      app: :fn_types,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Functional types library for Elixir with Result, Maybe, Pipeline, and more",
      package: package(),

      # Docs
      name: "FnTypes",
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:ex_unit, :mix]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Optional - for protocol implementations
      {:ecto, "~> 3.11", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      {:db_connection, ">= 0.0.0", optional: true},
      {:mint, ">= 0.0.0", optional: true},

      # Core (optional but recommended)
      {:nimble_options, "~> 1.0", optional: true},
      {:telemetry, "~> 1.0", optional: true},

      # Dev/Test
      {:mimic, "~> 1.7", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "FnTypes",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Core Types": [
          FnTypes.Result,
          FnTypes.Maybe,
          FnTypes.Pipeline,
          FnTypes.AsyncResult,
          FnTypes.Validation
        ],
        "Utility Types": [
          FnTypes.Error,
          FnTypes.Guards,
          FnTypes.Retry,
          FnTypes.Lens,
          FnTypes.Diff,
          FnTypes.NonEmptyList,
          FnTypes.Resource,
          FnTypes.Ior
        ],
        "Rate Limiting": [
          FnTypes.RateLimiter,
          FnTypes.Throttler,
          FnTypes.Debouncer
        ],
        Protocols: [
          FnTypes.Protocols.Normalizable,
          FnTypes.Protocols.Recoverable,
          FnTypes.Protocols.Identifiable
        ],
        "Error Types": [
          FnTypes.Errors.HttpError,
          FnTypes.Errors.PosixError
        ]
      ]
    ]
  end
end
