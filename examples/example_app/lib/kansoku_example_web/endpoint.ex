defmodule KansokuExampleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :kansoku_example

  @session_options [
    store: :cookie,
    key: "_kansoku_example_key",
    signing_salt: "kansoku-example"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug KansokuExampleWeb.Router
end
