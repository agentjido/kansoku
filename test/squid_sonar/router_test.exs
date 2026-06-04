defmodule SquidSonar.RouterTest do
  use ExUnit.Case, async: true

  defmodule HostRouter do
    use Phoenix.Router
    use SquidSonar.Router

    scope "/" do
      squid_sonar("/sonar")
    end
  end

  test "exports a router macro for embeddable mounting" do
    assert {:squid_sonar, 1} in SquidSonar.Router.__info__(:macros)
    assert {:squid_sonar, 2} in SquidSonar.Router.__info__(:macros)
  end

  test "mounts routes in a host Phoenix router" do
    routes = Phoenix.Router.routes(HostRouter)

    assert Enum.any?(
             routes,
             &(&1.path == "/sonar/css-:digest" and &1.plug == SquidSonarWeb.Assets)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/sonar/js-:digest" and &1.plug == SquidSonarWeb.Assets)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/sonar/vendor/phoenix-:digest" and &1.plug == SquidSonarWeb.Assets)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/sonar/vendor/live-view-:digest" and &1.plug == SquidSonarWeb.Assets)
           )

    assert Enum.any?(routes, &(&1.path == "/sonar" and &1.plug == Phoenix.LiveView.Plug))
    assert Enum.any?(routes, &(&1.path == "/sonar/runs/:id" and &1.plug == Phoenix.LiveView.Plug))
  end

  test "builds embeddable live session options" do
    assert {:squid_sonar, session_opts, [as: :squid_sonar]} =
             SquidSonar.Router.__options__("/dev/sonar", [])

    assert session_opts[:on_mount] == [SquidSonarWeb.Hooks]
    assert session_opts[:root_layout] == {SquidSonarWeb.Layouts, :root}

    assert {:session, {SquidSonar.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/dev/sonar",
             "/live",
             "websocket",
             SquidSonar.Router.default_control_actor()
           ]
  end

  test "supports custom route name and live transport settings" do
    assert {:ops_sonar, session_opts, [as: :ops_sonar]} =
             SquidSonar.Router.__options__(
               "/ops/sonar",
               as: :ops_sonar,
               socket_path: "/custom/live",
               transport: "longpoll"
             )

    assert {:session, {SquidSonar.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/ops/sonar",
             "/custom/live",
             "longpoll",
             SquidSonar.Router.default_control_actor()
           ]
  end

  test "supports static control actors" do
    actor = %{"id" => "user-123", "type" => "operator"}

    assert {:squid_sonar, session_opts, [as: :squid_sonar]} =
             SquidSonar.Router.__options__("/sonar", control_actor: actor)

    assert {:session, {SquidSonar.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == ["/sonar", "/live", "websocket", actor]
  end

  test "rejects invalid transport" do
    assert_raise ArgumentError, ~r/invalid :transport/, fn ->
      SquidSonar.Router.__options__("/sonar", transport: "invalid")
    end
  end

  test "builds live session payload" do
    assert %{
             "prefix" => "/sonar",
             "live_path" => "/live",
             "live_transport" => "websocket",
             "control_actor" => %{"id" => "squid_sonar"}
           } = SquidSonar.Router.__session__(%{}, "/sonar", "/live", "websocket")
  end

  test "builds live session payload with a dynamic control actor" do
    conn = Plug.Test.conn(:get, "/sonar")

    assert %{
             "control_actor" => %{"id" => "conn-user", "type" => "operator"}
           } =
             SquidSonar.Router.__session__(
               conn,
               "/sonar",
               "/live",
               "websocket",
               {__MODULE__, :control_actor_from_conn, []}
             )
  end

  @spec control_actor_from_conn(Plug.Conn.t()) :: map()
  def control_actor_from_conn(%Plug.Conn{}) do
    %{"id" => "conn-user", "type" => "operator"}
  end
end
