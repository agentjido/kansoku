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

    refute Enum.any?(routes, &(&1.path == "/sonar/runtime-specs/new"))
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
             SquidSonar.Router.default_control_actor(),
             nil,
             nil,
             nil
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
             SquidSonar.Router.default_control_actor(),
             nil,
             nil,
             nil
           ]
  end

  test "supports static control actors" do
    actor = %{"id" => "user-123", "type" => "operator"}

    assert {:squid_sonar, session_opts, [as: :squid_sonar]} =
             SquidSonar.Router.__options__("/sonar", control_actor: actor)

    assert {:session, {SquidSonar.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == ["/sonar", "/live", "websocket", actor, nil, nil, nil]
  end

  test "supports runtime specs catalog and action registry start boundaries" do
    specs = [checkout: %{workflow: RuntimeCheckout}]
    registry = %{"load_order" => __MODULE__}

    assert {:squid_sonar, session_opts, [as: :squid_sonar]} =
             SquidSonar.Router.__options__(
               "/sonar",
               runtime_specs: specs,
               action_registry: registry
             )

    assert {:session, {SquidSonar.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/sonar",
             "/live",
             "websocket",
             SquidSonar.Router.default_control_actor(),
             nil,
             registry,
             specs
           ]
  end

  test "supports runtime spec and action registry start boundaries" do
    spec = %{workflow: RuntimeCheckout}
    registry = %{"load_order" => __MODULE__}

    assert {:squid_sonar, session_opts, [as: :squid_sonar]} =
             SquidSonar.Router.__options__(
               "/sonar",
               runtime_spec: spec,
               action_registry: registry
             )

    assert {:session, {SquidSonar.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/sonar",
             "/live",
             "websocket",
             SquidSonar.Router.default_control_actor(),
             spec,
             registry,
             nil
           ]
  end

  test "rejects invalid transport" do
    assert_raise ArgumentError, ~r/invalid :transport/, fn ->
      SquidSonar.Router.__options__("/sonar", transport: "invalid")
    end
  end

  test "rejects non-keyed runtime specs catalogs" do
    assert_raise ArgumentError, ~r/invalid :runtime_specs/, fn ->
      SquidSonar.Router.__options__("/sonar", runtime_specs: [%{workflow: RuntimeCheckout}])
    end
  end

  test "builds live session payload" do
    assert %{
             "prefix" => "/sonar",
             "live_path" => "/live",
             "live_transport" => "websocket",
             "control_actor" => %{"id" => "squid_sonar"},
             "runtime_spec" => nil,
             "action_registry" => nil,
             "runtime_specs" => nil
           } = SquidSonar.Router.__session__(%{}, "/sonar", "/live", "websocket")
  end

  test "builds live session payload with a dynamic control actor" do
    conn = Plug.Test.conn(:get, "/sonar")

    assert session =
             %{
               "control_actor" => %{"id" => "conn-user", "type" => "operator"}
             } =
             SquidSonar.Router.__session__(
               conn,
               "/sonar",
               "/live",
               "websocket",
               {__MODULE__, :control_actor_from_conn, []},
               {__MODULE__, :runtime_spec_from_conn, []},
               {__MODULE__, :action_registry_from_conn, []},
               {__MODULE__, :runtime_specs_from_conn, []}
             )

    assert session["runtime_spec"] == %{workflow: RuntimeCheckout}
    assert session["action_registry"] == %{"load_order" => __MODULE__}
    assert session["runtime_specs"] == [checkout: %{workflow: RuntimeCheckout}]
  end

  test "rejects invalid runtime boundary values returned by callbacks" do
    conn = Plug.Test.conn(:get, "/sonar")

    assert_raise ArgumentError, ~r/invalid :runtime_spec/, fn ->
      SquidSonar.Router.__session__(
        conn,
        "/sonar",
        "/live",
        "websocket",
        SquidSonar.Router.default_control_actor(),
        {__MODULE__, :invalid_runtime_spec_from_conn, []},
        nil,
        nil
      )
    end

    assert_raise ArgumentError, ~r/invalid :action_registry/, fn ->
      SquidSonar.Router.__session__(
        conn,
        "/sonar",
        "/live",
        "websocket",
        SquidSonar.Router.default_control_actor(),
        nil,
        {__MODULE__, :invalid_action_registry_from_conn, []},
        nil
      )
    end

    assert_raise ArgumentError, ~r/invalid :runtime_specs/, fn ->
      SquidSonar.Router.__session__(
        conn,
        "/sonar",
        "/live",
        "websocket",
        SquidSonar.Router.default_control_actor(),
        nil,
        nil,
        {__MODULE__, :invalid_runtime_specs_from_conn, []}
      )
    end
  end

  @spec control_actor_from_conn(Plug.Conn.t()) :: map()
  def control_actor_from_conn(%Plug.Conn{}) do
    %{"id" => "conn-user", "type" => "operator"}
  end

  @spec runtime_spec_from_conn(Plug.Conn.t()) :: map()
  def runtime_spec_from_conn(%Plug.Conn{}), do: %{workflow: RuntimeCheckout}

  @spec action_registry_from_conn(Plug.Conn.t()) :: map()
  def action_registry_from_conn(%Plug.Conn{}), do: %{"load_order" => __MODULE__}

  @spec runtime_specs_from_conn(Plug.Conn.t()) :: keyword(map())
  def runtime_specs_from_conn(%Plug.Conn{}), do: [checkout: %{workflow: RuntimeCheckout}]

  @spec invalid_runtime_spec_from_conn(Plug.Conn.t()) :: term()
  def invalid_runtime_spec_from_conn(%Plug.Conn{}), do: :not_a_spec

  @spec invalid_action_registry_from_conn(Plug.Conn.t()) :: term()
  def invalid_action_registry_from_conn(%Plug.Conn{}), do: [:not_a_registry]

  @spec invalid_runtime_specs_from_conn(Plug.Conn.t()) :: term()
  def invalid_runtime_specs_from_conn(%Plug.Conn{}), do: [%{workflow: RuntimeCheckout}]
end
