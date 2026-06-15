defmodule SquidSonarExampleWeb.Router do
  use Phoenix.Router
  use SquidSonar.Router

  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SquidSonarExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", SquidSonarExampleWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/" do
    pipe_through :browser

    squid_sonar("/sonar",
      otp_app: :squid_sonar_example,
      runtime_specs: {SquidSonarExample.RuntimeSpecDemo, :runtime_specs, []},
      saved_specs: {SquidSonarExample.RuntimeSpecDemo, :saved_specs, []},
      action_registry: {SquidSonarExample.RuntimeSpecDemo, :action_registry, []}
    )
  end
end
