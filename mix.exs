defmodule Events.MixProject do
  use Mix.Project

  def project do
    [
      app: :events,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # Xref checks for compile-time analysis
      xref: [exclude: xref_excludes()],
      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "test.interactive": :test,
        "test.quality": :test
      ]
    ]
  end

  # Exclude known compile-time dependencies from xref warnings
  defp xref_excludes do
    [
      # Ecto internal macros
      {Ecto.Migration, :add, 2},
      {Ecto.Migration, :add, 3},
      {Ecto.Migration, :create, 1},
      {Ecto.Migration, :create, 2},
      {Ecto.Migration, :index, 2},
      {Ecto.Migration, :index, 3},
      {Ecto.Migration, :table, 1},
      {Ecto.Migration, :table, 2}
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Events.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:decorator, "~> 1.4"},
      {:deco, "~> 0.1.2"},
      {:nebulex, "~> 2.6"},
      {:nebulex_redis_adapter, "~> 2.4"},
      {:req_s3, "~> 0.2.3"},
      {:hammer, "~> 6.2"},
      {:hammer_backend_redis, "~> 6.2"},
      {:redix, "~> 1.5"},
      {:phoenix_pubsub_redis, "~> 3.0"},
      # Authentication
      {:bcrypt_elixir, "~> 3.0"},
      # Benchmarking
      {:benchee, "~> 1.3", only: :dev},
      # Static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # ============================================
      # Testing Libraries
      # ============================================

      # Mocking - Mimic for ad-hoc mocking, Hammox for contract-enforced mocking
      {:mimic, "~> 2.0", only: :test},
      {:hammox, "~> 0.7", only: :test},

      # Effects - Declarative side-effect isolation
      {:efx, "~> 1.0", only: :test},

      # HTTP Testing - Mock server with TLS/HTTP2 support
      {:test_server, "~> 0.1", only: :test},

      # Data Generation
      {:faker, "~> 0.18", only: :test},

      # Property-Based Testing
      {:stream_data, "~> 1.1", only: :test},

      # Test Coverage
      {:excoveralls, "~> 0.18", only: :test},

      # Development - Watch mode test runner
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},

      # Documentation coverage
      {:doctor, "~> 0.22", only: :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind events", "esbuild events"],
      "assets.deploy": [
        "tailwind events --minify",
        "esbuild events --minify",
        "phx.digest"
      ],

      # ============================================
      # Quality & Testing Aliases
      # ============================================

      # Pre-commit hook - fast quality checks
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --warnings-as-errors"
      ],

      # Full CI pipeline
      ci: [
        "deps.unlock --check-unused",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --warnings-as-errors --cover"
      ],

      # Test quality - comprehensive test validation
      "test.quality": [
        "compile --warnings-as-errors",
        "test --warnings-as-errors"
      ],

      # Test with coverage report
      "test.coverage": ["test --cover"],
      "test.coverage.html": ["coveralls.html"],

      # Run only fast unit tests (exclude integration/slow)
      "test.unit": ["test --exclude integration --exclude slow --exclude external"],

      # Run integration tests only
      "test.integration": ["test --only integration"],

      # Run external API tests only (requires network)
      "test.external": ["test --only external"],

      # Property-based tests
      "test.properties": ["test --only property"],

      # Static analysis
      lint: ["format --check-formatted", "credo --strict"],

      # Check for circular dependencies
      "xref.check": ["xref graph --label compile-connected --fail-above 50"],

      # Documentation coverage
      "docs.coverage": ["doctor"]
    ]
  end
end
