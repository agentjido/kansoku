import Config

config :kansoku_example, KansokuExample.Repo,
  url:
    System.get_env("DATABASE_URL") ||
      "postgres://postgres:postgres@localhost:5432/kansoku_example_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :kansoku_example, KansokuExampleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4011],
  secret_key_base: "kansoku_example_test_secret_key_base_at_least_sixty_four_bytes_long",
  server: false

config :kansoku_example, :journal_run, enabled: false

config :logger, level: :warning
