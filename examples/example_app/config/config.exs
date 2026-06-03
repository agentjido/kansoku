import Config

config :squid_sonar_example,
  ecto_repos: [SquidSonarExample.Repo]

config :squid_sonar_example, SquidSonarExampleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SquidSonarExampleWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: SquidSonarExample.PubSub,
  live_view: [signing_salt: "squid-sonar-example"]

config :squidie,
  repo: SquidSonarExample.Repo,
  executor: SquidSonarExample.SquidieExecutor

import_config "#{config_env()}.exs"
