defmodule Kansoku.MixProject do
  use Mix.Project

  def project do
    [
      app: :kansoku,
      version: "0.4.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      source_url: "https://github.com/dark-trench/kansoku",
      homepage_url: "https://github.com/dark-trench/kansoku",
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
    "Embeddable runtime dashboard for Jizoku."
  end

  defp package do
    [
      name: "kansoku",
      maintainers: ["Cristiano Carvalho"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/dark-trench/kansoku"},
      files:
        ~w(lib priv .formatter.exs mix.exs README* MIGRATION* CHANGELOG* LICENSE* CONTRIBUTING*)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "MIGRATION.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.6"},
      {:jason, "~> 1.4"},
      jizoku_dep(),
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

  defp jizoku_dep do
    case System.get_env("KANSOKU_JIZOKU_SOURCE") do
      "hex" ->
        {:jizoku, "~> 0.4.0"}

      _source ->
        {:jizoku,
         git: "https://github.com/tsuranari/jizoku.git",
         ref: "a4f13e0a47a3848f8a52196610ed15f567417c77"}
    end
  end

  defp aliases do
    [
      {:quality_gates, ["quality_gates.ex_dna", "quality_gates.reach"]},
      {:"brand.audit", ["run scripts/kansoku_rebrand_audit.exs"]},
      {:"quality_gates.ex_dna", ["ex_dna --min-mass 40 --max-clones 0 --format console"]},
      {:"quality_gates.reach", ["reach.check --smells --strict"]},
      {:precommit,
       [
         "compile --warnings-as-errors",
         "xref graph --format cycles --label compile-connected --fail-above 0",
         "brand.audit",
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
