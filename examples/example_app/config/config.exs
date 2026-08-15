import Config

config :kansoku_example,
  ecto_repos: [KansokuExample.Repo]

config :kansoku_example, KansokuExampleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KansokuExampleWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: KansokuExample.PubSub,
  live_view: [signing_salt: "kansoku-example"]

config :jizoku,
  repo: KansokuExample.Repo,
  executor: KansokuExample.JizokuExecutor

import_config "#{config_env()}.exs"
