import Config

config :kansoku_example, KansokuExample.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kansoku_example_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :kansoku_example, KansokuExampleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kansoku_example_dev_secret_key_base_at_least_sixty_four_bytes_long"

config :logger, :console, format: "[$level] $message\n"
