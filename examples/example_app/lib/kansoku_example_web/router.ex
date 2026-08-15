defmodule KansokuExampleWeb.Router do
  use Phoenix.Router
  use Kansoku.Router

  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KansokuExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", KansokuExampleWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/" do
    pipe_through :browser

    kansoku("/kansoku",
      otp_app: :kansoku_example,
      runtime_specs: {KansokuExample.RuntimeSpecDemo, :runtime_specs, []},
      saved_specs: {KansokuExample.RuntimeSpecDemo, :saved_specs, []},
      action_registry: {KansokuExample.RuntimeSpecDemo, :action_registry, []}
    )
  end
end
