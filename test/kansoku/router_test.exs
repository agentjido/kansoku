defmodule Kansoku.RouterTest do
  use ExUnit.Case, async: true

  alias KansokuWeb.Hooks
  alias Phoenix.LiveView.Socket

  defmodule VisibilityActor do
    @spec resolve(Plug.Conn.t() | map(), String.t()) :: String.t()
    def resolve(conn, suffix), do: "#{conn.assigns.user_id}-#{suffix}"
  end

  defmodule HostRouter do
    use Phoenix.Router
    use Kansoku.Router

    scope "/" do
      kansoku("/kansoku")
    end
  end

  test "exports a router macro for embeddable mounting" do
    assert {:kansoku, 1} in Kansoku.Router.__info__(:macros)
    assert {:kansoku, 2} in Kansoku.Router.__info__(:macros)
  end

  test "mounts routes in a host Phoenix router" do
    routes = Phoenix.Router.routes(HostRouter)

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/css-:digest" and &1.plug == KansokuWeb.Assets)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/js-:digest" and &1.plug == KansokuWeb.Assets)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/vendor/phoenix-:digest" and &1.plug == KansokuWeb.Assets)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/vendor/live-view-:digest" and &1.plug == KansokuWeb.Assets)
           )

    assert Enum.any?(routes, &(&1.path == "/kansoku" and &1.plug == Phoenix.LiveView.Plug))
    assert Enum.any?(routes, &(&1.path == "/kansoku/queues" and &1.plug == Phoenix.LiveView.Plug))

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/settings" and &1.plug == Phoenix.LiveView.Plug)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/runs/:id" and &1.plug == Phoenix.LiveView.Plug)
           )

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/saved-specs/:key" and &1.plug == Phoenix.LiveView.Plug)
           )

    refute Enum.any?(routes, &(&1.path == "/kansoku/runtime-specs/new"))
  end

  test "builds embeddable live session options" do
    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__("/dev/kansoku", [])

    assert session_opts[:on_mount] == [KansokuWeb.Hooks]
    assert session_opts[:root_layout] == {KansokuWeb.Layouts, :root}

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/dev/kansoku",
             "/live",
             "websocket",
             Kansoku.Router.default_control_actor(),
             nil,
             nil,
             %{saved_specs: nil, runtime_specs: nil}
           ]
  end

  test "supports custom route name and live transport settings" do
    assert {:ops_kansoku, session_opts, [as: :ops_kansoku]} =
             Kansoku.Router.__options__(
               "/ops/kansoku",
               as: :ops_kansoku,
               socket_path: "/custom/live",
               transport: "longpoll"
             )

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/ops/kansoku",
             "/custom/live",
             "longpoll",
             Kansoku.Router.default_control_actor(),
             nil,
             nil,
             %{saved_specs: nil, runtime_specs: nil}
           ]
  end

  test "supports static control actors" do
    actor = %{"id" => "user-123", "type" => "operator"}

    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__("/kansoku", control_actor: actor)

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/kansoku",
             "/live",
             "websocket",
             actor,
             nil,
             nil,
             %{saved_specs: nil, runtime_specs: nil}
           ]
  end

  test "supports actor-scoped read visibility" do
    actor = "viewer-123"

    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__(
               "/kansoku",
               visibility_actor: actor,
               visibility_policy: :external
             )

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    [_prefix, _live_path, _transport, _control_actor, _runtime_spec, _registry, runtime_options] =
      session_args

    assert %{visibility_actor: ^actor, visibility_policy: :external} = runtime_options
  end

  test "resolves an opaque visibility actor and propagates it through the mount hook" do
    actor_mfa = {VisibilityActor, :resolve, ["active"]}

    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__(
               "/kansoku",
               visibility_actor: actor_mfa,
               visibility_policy: :external
             )

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    session =
      apply(Kansoku.Router, :__session__, [
        %{assigns: %{user_id: "user-42"}} | session_args
      ])

    assert session["visibility_actor"] == "user-42-active"
    assert session["visibility_policy"] == :external

    assert {:cont, socket} = Hooks.on_mount(:default, %{}, session, %Socket{})
    assert socket.assigns.visibility_actor == "user-42-active"
    assert socket.assigns.visibility_policy == :external
  end

  test "rejects non-opaque visibility actor configuration" do
    assert_raise ArgumentError, ~r/invalid :visibility_actor/, fn ->
      Kansoku.Router.__options__("/kansoku", visibility_actor: %{role: :admin})
    end
  end

  test "supports runtime specs catalog and action registry start boundaries" do
    specs = [checkout: %{workflow: RuntimeCheckout}]
    registry = %{"load_order" => __MODULE__}

    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__(
               "/kansoku",
               runtime_specs: specs,
               action_registry: registry
             )

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/kansoku",
             "/live",
             "websocket",
             Kansoku.Router.default_control_actor(),
             nil,
             registry,
             %{saved_specs: nil, runtime_specs: specs}
           ]
  end

  test "supports runtime spec and action registry start boundaries" do
    spec = %{workflow: RuntimeCheckout}
    registry = %{"load_order" => __MODULE__}

    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__(
               "/kansoku",
               runtime_spec: spec,
               action_registry: registry
             )

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/kansoku",
             "/live",
             "websocket",
             Kansoku.Router.default_control_actor(),
             spec,
             registry,
             %{saved_specs: nil, runtime_specs: nil}
           ]
  end

  test "supports saved spec catalog and action registry boundaries" do
    saved_specs = [
      checkout_runtime_spec: %{
        title: "Checkout runtime spec",
        status: :approved,
        editor_json: %{"workflow" => "RuntimeCheckout"}
      }
    ]

    registry = %{"load_order" => __MODULE__}

    assert {:kansoku, session_opts, [as: :kansoku]} =
             Kansoku.Router.__options__(
               "/kansoku",
               saved_specs: saved_specs,
               action_registry: registry
             )

    assert {:session, {Kansoku.Router, :__session__, session_args}} =
             List.keyfind(session_opts, :session, 0)

    assert session_args == [
             "/kansoku",
             "/live",
             "websocket",
             Kansoku.Router.default_control_actor(),
             nil,
             registry,
             %{saved_specs: saved_specs, runtime_specs: nil}
           ]
  end

  test "rejects invalid transport" do
    assert_raise ArgumentError, ~r/invalid :transport/, fn ->
      Kansoku.Router.__options__("/kansoku", transport: "invalid")
    end
  end

  test "rejects non-keyed runtime specs catalogs" do
    assert_raise ArgumentError, ~r/invalid :runtime_specs/, fn ->
      Kansoku.Router.__options__("/kansoku", runtime_specs: [%{workflow: RuntimeCheckout}])
    end
  end

  test "builds live session payload" do
    assert %{
             "prefix" => "/kansoku",
             "live_path" => "/live",
             "live_transport" => "websocket",
             "control_actor" => %{"id" => "kansoku"},
             "runtime_spec" => nil,
             "action_registry" => nil,
             "saved_specs" => nil,
             "runtime_specs" => nil,
             "visibility_actor" => "kansoku",
             "visibility_policy" => :operator
           } = Kansoku.Router.__session__(%{}, "/kansoku", "/live", "websocket")
  end

  test "builds live session payload with a dynamic control actor" do
    conn = Plug.Test.conn(:get, "/kansoku")

    assert session =
             %{
               "control_actor" => %{"id" => "conn-user", "type" => "operator"}
             } =
             Kansoku.Router.__session__(
               conn,
               "/kansoku",
               "/live",
               "websocket",
               {__MODULE__, :control_actor_from_conn, []},
               {__MODULE__, :runtime_spec_from_conn, []},
               {__MODULE__, :action_registry_from_conn, []},
               %{
                 saved_specs: {__MODULE__, :saved_specs_from_conn, []},
                 runtime_specs: {__MODULE__, :runtime_specs_from_conn, []}
               }
             )

    assert session["runtime_spec"] == %{workflow: RuntimeCheckout}
    assert session["action_registry"] == %{"load_order" => __MODULE__}
    assert session["saved_specs"] == [checkout_runtime_spec: %{title: "Checkout runtime spec"}]
    assert session["runtime_specs"] == [checkout: %{workflow: RuntimeCheckout}]
  end

  test "rejects invalid runtime boundary values returned by callbacks" do
    conn = Plug.Test.conn(:get, "/kansoku")

    assert_raise ArgumentError, ~r/invalid :runtime_spec/, fn ->
      Kansoku.Router.__session__(
        conn,
        "/kansoku",
        "/live",
        "websocket",
        Kansoku.Router.default_control_actor(),
        {__MODULE__, :invalid_runtime_spec_from_conn, []},
        nil,
        nil
      )
    end

    assert_raise ArgumentError, ~r/invalid :action_registry/, fn ->
      Kansoku.Router.__session__(
        conn,
        "/kansoku",
        "/live",
        "websocket",
        Kansoku.Router.default_control_actor(),
        nil,
        {__MODULE__, :invalid_action_registry_from_conn, []},
        nil
      )
    end

    assert_raise ArgumentError, ~r/invalid :runtime_specs/, fn ->
      Kansoku.Router.__session__(
        conn,
        "/kansoku",
        "/live",
        "websocket",
        Kansoku.Router.default_control_actor(),
        nil,
        nil,
        {__MODULE__, :invalid_runtime_specs_from_conn, []}
      )
    end

    assert_raise ArgumentError, ~r/invalid :saved_specs/, fn ->
      Kansoku.Router.__session__(
        conn,
        "/kansoku",
        "/live",
        "websocket",
        Kansoku.Router.default_control_actor(),
        nil,
        nil,
        %{saved_specs: {__MODULE__, :invalid_saved_specs_from_conn, []}}
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

  @spec saved_specs_from_conn(Plug.Conn.t()) :: keyword(map())
  def saved_specs_from_conn(%Plug.Conn{}) do
    [checkout_runtime_spec: %{title: "Checkout runtime spec"}]
  end

  @spec invalid_runtime_spec_from_conn(Plug.Conn.t()) :: term()
  def invalid_runtime_spec_from_conn(%Plug.Conn{}), do: :not_a_spec

  @spec invalid_action_registry_from_conn(Plug.Conn.t()) :: term()
  def invalid_action_registry_from_conn(%Plug.Conn{}), do: [:not_a_registry]

  @spec invalid_runtime_specs_from_conn(Plug.Conn.t()) :: term()
  def invalid_runtime_specs_from_conn(%Plug.Conn{}), do: [%{workflow: RuntimeCheckout}]

  @spec invalid_saved_specs_from_conn(Plug.Conn.t()) :: term()
  def invalid_saved_specs_from_conn(%Plug.Conn{}), do: [%{title: "not keyed"}]
end
