defmodule SquidSonar.Router do
  @moduledoc """
  Router helpers for mounting SquidSonar inside a Phoenix application.

  The host owns its endpoint, authentication, layout, and deployment topology.
  SquidSonar contributes only the LiveView routes under the requested path.
  """

  @default_opts [
    socket_path: "/live",
    transport: "websocket"
  ]

  @default_control_actor %{
    "id" => "squid_sonar",
    "type" => "system",
    "name" => "SquidSonar operator"
  }

  @transport_values ~w(longpoll websocket)

  defmacro __using__(_opts) do
    quote do
      import SquidSonar.Router, only: [squid_sonar: 1, squid_sonar: 2]
    end
  end

  @doc """
  Mounts SquidSonar under the given path.

      scope "/" do
        pipe_through [:browser]

        squid_sonar "/sonar"
      end

  Supported options:

    * `:as` - route helper name for the mounted LiveView session.
    * `:socket_path` - LiveView socket path used by the host application.
      Defaults to `"/live"`.
    * `:transport` - LiveView client transport. Use `"websocket"` or
      `"longpoll"`. Defaults to `"websocket"`.
    * `:control_actor` - actor persisted with Squidie manual approval and
      resume actions. Pass a non-empty binary, a non-empty map, or an MFA tuple
      `{module, function, args}`. MFA callbacks receive the current `conn` as
      their first argument.
  """
  defmacro squid_sonar(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts, route_opts} = SquidSonar.Router.__options__(prefix, opts)

        live_session session_name, session_opts do
          get "/css-:digest", SquidSonarWeb.Assets, :css, as: :squid_sonar_asset
          get "/js-:digest", SquidSonarWeb.Assets, :js, as: :squid_sonar_js
          get "/vendor/phoenix-:digest", SquidSonarWeb.Assets, :phoenix, as: :squid_sonar_phoenix

          get "/vendor/live-view-:digest", SquidSonarWeb.Assets, :live_view,
            as: :squid_sonar_live_view

          live "/", SquidSonarWeb.PageLive, :index, route_opts
          live "/runs/:id", SquidSonarWeb.RunLive, :show, route_opts
        end
      end
    end
  end

  @doc """
  Normalizes mount options for the generated SquidSonar route block.
  """
  @spec __options__(String.t(), keyword()) :: {atom(), keyword(), keyword()}
  def __options__(prefix, opts) do
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(opts, &validate_opt!/1)

    session_args = [
      prefix,
      opts[:socket_path],
      opts[:transport],
      Keyword.get(opts, :control_actor, @default_control_actor)
    ]

    session_opts = [
      on_mount: [SquidSonarWeb.Hooks],
      session: {__MODULE__, :__session__, session_args},
      root_layout: {SquidSonarWeb.Layouts, :root}
    ]

    session_name = Keyword.get(opts, :as, :squid_sonar)

    {session_name, session_opts, as: session_name}
  end

  @doc """
  Builds the LiveView session with the default manual-control actor.
  """
  @spec __session__(Plug.Conn.t() | map(), String.t(), String.t(), String.t()) :: map()
  def __session__(_conn, prefix, live_path, live_transport) do
    __session__(%{}, prefix, live_path, live_transport, @default_control_actor)
  end

  @doc """
  Builds the LiveView session and resolves the configured manual-control actor.
  """
  @spec __session__(Plug.Conn.t() | map(), String.t(), String.t(), String.t(), term()) :: map()
  def __session__(conn, prefix, live_path, live_transport, control_actor) do
    %{
      "prefix" => prefix,
      "live_path" => live_path,
      "live_transport" => live_transport,
      "control_actor" => resolve_control_actor(conn, control_actor)
    }
  end

  @doc """
  Returns the default manual-control actor used when the host does not provide one.
  """
  @spec default_control_actor() :: map()
  def default_control_actor, do: @default_control_actor

  defp validate_opt!({:transport, transport}) do
    unless transport in @transport_values do
      raise ArgumentError, """
      invalid :transport, expected one of #{inspect(@transport_values)},
      got #{inspect(transport)}
      """
    end
  end

  defp validate_opt!({:socket_path, path}) do
    unless is_binary(path) and byte_size(path) > 0 do
      raise ArgumentError, """
      invalid :socket_path, expected a non-empty binary URL,
      got #{inspect(path)}
      """
    end
  end

  defp validate_opt!({:as, name}) do
    unless is_atom(name) do
      raise ArgumentError, """
      invalid :as, expected an atom route name,
      got #{inspect(name)}
      """
    end
  end

  defp validate_opt!({:control_actor, actor}) do
    unless valid_control_actor_spec?(actor) do
      raise ArgumentError, """
      invalid :control_actor, expected a non-empty binary, non-empty map,
      or {module, function, args} tuple, got #{inspect(actor)}
      """
    end
  end

  defp validate_opt!(_option), do: :ok

  defp valid_control_actor_spec?(actor) when is_binary(actor), do: actor != ""
  defp valid_control_actor_spec?(actor) when is_map(actor), do: map_size(actor) > 0

  defp valid_control_actor_spec?({module, function, args}) do
    is_atom(module) and is_atom(function) and is_list(args)
  end

  defp valid_control_actor_spec?(_actor), do: false

  defp resolve_control_actor(conn, {module, function, args}) do
    conn
    |> then(&apply(module, function, [&1 | args]))
    |> normalize_control_actor()
  end

  defp resolve_control_actor(_conn, actor), do: normalize_control_actor(actor)

  defp normalize_control_actor(actor) when is_binary(actor) and actor != "", do: actor
  defp normalize_control_actor(actor) when is_map(actor) and map_size(actor) > 0, do: actor
  defp normalize_control_actor(_actor), do: @default_control_actor
end
