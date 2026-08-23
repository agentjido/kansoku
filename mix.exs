defmodule Kansoku.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/agentjido/kansoku"
  @description "Embeddable runtime dashboard for Jizoku."

  def project do
    [
      app: :kansoku,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls, summary: [threshold: 80], export: "cov"],
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
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        precommit: :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "kansoku",
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/kansoku/changelog.html",
        "Discord" => "https://jido.run/discord",
        "Documentation" => "https://hexdocs.pm/kansoku",
        "GitHub" => @source_url,
        "Website" => "https://jido.run"
      },
      files:
        ~w(lib priv usage-rules.md .formatter.exs mix.exs README* MIGRATION* CHANGELOG* LICENSE* CONTRIBUTING*)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "MIGRATION.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "usage-rules.md",
        "LICENSE"
      ]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.6"},
      {:jason, "~> 1.4"},
      {:jizoku, "~> 0.4.0"},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      {:setup, ["deps.get"]},
      {:install_hooks, ["git_hooks.install"]},
      {:q, ["quality"]},
      {:quality,
       [
         "format --check-formatted",
         "compile --warnings-as-errors",
         "credo --min-priority higher",
         "dialyzer",
         "doctor --raise"
       ]},
      {:quality_gates, ["quality_gates.ex_dna", "quality_gates.reach"]},
      {:"brand.audit", ["run scripts/kansoku_rebrand_audit.exs"]},
      {:"quality_gates.ex_dna", ["ex_dna --min-mass 40 --max-clones 0 --format console"]},
      {:"quality_gates.reach", ["reach.check --smells --strict"]},
      {:precommit,
       [
         "compile --warnings-as-errors",
         "xref graph --format cycles --label compile-connected --fail-above 0",
         "deps.unlock --check-unused",
         "brand.audit",
         "format --check-formatted",
         "credo --strict",
         "doctor --raise",
         "deps.audit",
         "dialyzer",
         "quality_gates",
         "test"
       ]}
    ]
  end
end
