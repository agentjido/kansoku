import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is required for the example app in production"

  config :kansoku_example, KansokuExample.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is required for the example app in production"

  config :kansoku_example, KansokuExampleWeb.Endpoint, secret_key_base: secret_key_base
end
