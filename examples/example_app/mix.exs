defmodule KansokuExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :kansoku_example,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {KansokuExample.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.6"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.7"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.20"},
      {:jizoku, "~> 0.4.0"},
      {:kansoku, path: "../.."}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test"
      ]
    ]
  end
end
