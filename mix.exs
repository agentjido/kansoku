defmodule SquidSonar.MixProject do
  use Mix.Project

  def project do
    [
      app: :squid_sonar,
      version: "0.1.7",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      source_url: "https://github.com/dark-trench/squid_sonar",
      homepage_url: "https://github.com/dark-trench/squid_sonar",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Embeddable runtime dashboard for Squidie."
  end

  defp package do
    [
      name: "squid_sonar",
      maintainers: ["Cristiano Carvalho"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/dark-trench/squid_sonar"},
      files: ~w(lib priv .formatter.exs mix.exs README* CHANGELOG* LICENSE* CONTRIBUTING*)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1"},
      {:jason, "~> 1.4"},
      squidie_dep(),
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp squidie_dep do
    {:squidie, "~> 0.1.2"}
  end

  defp aliases do
    [
      {:quality_gates, ["quality_gates.ex_dna", "quality_gates.reach"]},
      {:"quality_gates.ex_dna", ["ex_dna --min-mass 40 --max-clones 0 --format console"]},
      {:"quality_gates.reach", ["reach.check --smells --strict"]},
      {:precommit,
       [
         "compile --warnings-as-errors",
         "xref graph --format cycles --label compile-connected --fail-above 0",
         "format --check-formatted",
         "credo --strict",
         "doctor",
         "deps.audit",
         "dialyzer",
         "quality_gates",
         "test"
       ]}
    ]
  end
end
