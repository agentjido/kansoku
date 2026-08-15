defmodule KansokuExample.Repo do
  use Ecto.Repo,
    otp_app: :kansoku_example,
    adapter: Ecto.Adapters.Postgres
end
