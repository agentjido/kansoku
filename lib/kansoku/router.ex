defmodule Kansoku.Router do
  @moduledoc """
  Router helpers for mounting Kansoku inside a Phoenix application.

  The host owns its endpoint, authentication, layout, and deployment topology.
  Kansoku contributes only the LiveView routes under the requested path.
  """

  @default_opts [
    socket_path: "/live",
    transport: "websocket"
  ]

  @default_control_actor %{
    "id" => "kansoku",
    "type" => "system",
    "name" => "Kansoku operator"
  }

  @transport_values ~w(longpoll websocket)

  defmacro __using__(_opts) do
    quote do
      import Kansoku.Router, only: [kansoku: 1, kansoku: 2]
    end
  end

  @doc """
  Mounts Kansoku under the given path.

      scope "/" do
        pipe_through [:browser]

        kansoku "/kansoku"
      end

  Supported options:

    * `:as` - route helper name for the mounted LiveView session.
    * `:socket_path` - LiveView socket path used by the host application.
      Defaults to `"/live"`.
    * `:transport` - LiveView client transport. Use `"websocket"` or
      `"longpoll"`. Defaults to `"websocket"`.
    * `:control_actor` - actor persisted with Jizoku manual approval and
      resume actions. Pass a non-empty binary, a non-empty map, or an MFA tuple
      `{module, function, args}`. MFA callbacks receive the current `conn` as
      their first argument.
    * `:visibility_actor` - actor passed to Jizoku's read visibility policy.
      Pass a non-empty opaque identifier or an MFA tuple that returns one. It
      defaults to the resolved control actor's `id` field. This value is stored
      in a signed, client-readable LiveView session, so it must not contain
      secrets, personal data, roles, or a full user struct.
    * `:visibility_policy` - Jizoku visibility scope, policy module, or
      `{module, opts}` tuple. Defaults to `:operator`. Module policies should
      revalidate current server-side authorization from the opaque actor id.
    * `:runtime_specs` - host-approved workflow catalog used by the dashboard
      start drawer. Pass a keyword list or map of stable keys to workflow modules
      or runtime specs, or an MFA tuple `{module, function, args}`. Workflow
      module entries start through `Jizoku.start/3`; runtime spec entries start
      through `Jizoku.start_spec/3`.
    * `:runtime_spec` - single runtime-authored workflow spec used by the
      dashboard start drawer. Prefer `:runtime_specs` for new integrations.
      Pass a map/struct or an MFA tuple `{module, function, args}`.
    * `:action_registry` - host-owned action registry passed to
      `Jizoku.start_spec/3` for runtime spec entries. Pass a map, keyword list,
      or MFA tuple. Keep credentials and private action options outside this
      registry because the resolved value is stored in the signed,
      client-readable LiveView session.
    * `:saved_specs` - host-owned saved workflow spec records surfaced by
      Kansoku. Pass a keyword list or map of stable keys to saved-spec
      metadata, or an MFA tuple `{module, function, args}`. The host owns
      persistence, approval, action registry policy, and activation decisions.
      Saved records are also client-readable and must not contain secrets or
      tenant-private data.
  """
  defmacro kansoku(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts, route_opts} = Kansoku.Router.__options__(prefix, opts)

        live_session session_name, session_opts do
          get "/css-:digest", KansokuWeb.Assets, :css, as: :kansoku_asset
          get "/js-:digest", KansokuWeb.Assets, :js, as: :kansoku_js
          get "/vendor/phoenix-:digest", KansokuWeb.Assets, :phoenix, as: :kansoku_phoenix

          get "/vendor/live-view-:digest", KansokuWeb.Assets, :live_view, as: :kansoku_live_view

          live "/", KansokuWeb.PageLive, :index, route_opts
          live "/queues", KansokuWeb.OperatorQueuesLive, :index, route_opts
          live "/settings", KansokuWeb.SettingsLive, :index, route_opts
          live "/saved-specs/:key", KansokuWeb.SavedSpecLive, :show, route_opts
          live "/runs/:id", KansokuWeb.RunLive, :show, route_opts
        end
      end
    end
  end

  @doc """
  Normalizes mount options for the generated Kansoku route block.
  """
  @spec __options__(String.t(), keyword()) :: {atom(), keyword(), keyword()}
  def __options__(prefix, opts) do
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(opts, &validate_opt!/1)

    runtime_options =
      %{
        saved_specs: Keyword.get(opts, :saved_specs),
        runtime_specs: Keyword.get(opts, :runtime_specs)
      }
      |> maybe_put(:visibility_actor, Keyword.get(opts, :visibility_actor))
      |> maybe_put(:visibility_policy, Keyword.get(opts, :visibility_policy))

    session_args = [
      prefix,
      opts[:socket_path],
      opts[:transport],
      Keyword.get(opts, :control_actor, @default_control_actor),
      Keyword.get(opts, :runtime_spec),
      Keyword.get(opts, :action_registry),
      runtime_options
    ]

    session_opts = [
      on_mount: [KansokuWeb.Hooks],
      session: {__MODULE__, :__session__, session_args},
      root_layout: {KansokuWeb.Layouts, :root}
    ]

    session_name = Keyword.get(opts, :as, :kansoku)

    {session_name, session_opts, as: session_name}
  end

  @doc """
  Builds the LiveView session with the default manual-control actor.
  """
  @spec __session__(Plug.Conn.t() | map(), String.t(), String.t(), String.t()) :: map()
  def __session__(_conn, prefix, live_path, live_transport) do
    __session__(
      %{},
      prefix,
      live_path,
      live_transport,
      @default_control_actor,
      nil,
      nil,
      nil
    )
  end

  @doc """
  Builds the LiveView session and resolves the configured manual-control actor.
  """
  @spec __session__(Plug.Conn.t() | map(), String.t(), String.t(), String.t(), term()) :: map()
  def __session__(conn, prefix, live_path, live_transport, control_actor) do
    __session__(conn, prefix, live_path, live_transport, control_actor, nil, nil, nil)
  end

  @doc """
  Builds the LiveView session and resolves host-provided runtime spec options.
  """
  @spec __session__(
          Plug.Conn.t() | map(),
          String.t(),
          String.t(),
          String.t(),
          term(),
          term(),
          term()
        ) :: map()
  def __session__(
        conn,
        prefix,
        live_path,
        live_transport,
        control_actor,
        runtime_spec,
        action_registry
      ) do
    __session__(
      conn,
      prefix,
      live_path,
      live_transport,
      control_actor,
      runtime_spec,
      action_registry,
      nil
    )
  end

  @doc """
  Builds the LiveView session and resolves host-provided runtime spec catalog options.
  """
  @spec __session__(
          Plug.Conn.t() | map(),
          String.t(),
          String.t(),
          String.t(),
          term(),
          term(),
          term(),
          term()
        ) :: map()
  def __session__(
        conn,
        prefix,
        live_path,
        live_transport,
        control_actor,
        runtime_spec,
        action_registry,
        runtime_options
      ) do
    {saved_specs_config, runtime_specs_config, visibility_actor_config, visibility_policy} =
      runtime_session_options(runtime_options)

    runtime_spec = resolve_session_value(conn, runtime_spec)
    action_registry = resolve_session_value(conn, action_registry)
    saved_specs = resolve_session_value(conn, saved_specs_config)
    runtime_specs = resolve_session_value(conn, runtime_specs_config)
    control_actor = resolve_control_actor(conn, control_actor)

    visibility_actor = resolve_visibility_actor(conn, visibility_actor_config, control_actor)

    validate_runtime_spec!(:runtime_spec, runtime_spec)
    validate_action_registry!(:action_registry, action_registry)
    validate_saved_specs!(:saved_specs, saved_specs)
    validate_runtime_specs!(:runtime_specs, runtime_specs)
    validate_visibility_policy!(:visibility_policy, visibility_policy)

    %{
      "prefix" => prefix,
      "live_path" => live_path,
      "live_transport" => live_transport,
      "control_actor" => control_actor,
      "runtime_spec" => runtime_spec,
      "action_registry" => action_registry,
      "saved_specs" => saved_specs,
      "runtime_specs" => runtime_specs,
      "visibility_actor" => visibility_actor,
      "visibility_policy" => visibility_policy
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

  defp validate_opt!({:visibility_actor, actor}) do
    unless valid_visibility_actor_spec?(actor) do
      raise ArgumentError, """
      invalid :visibility_actor, expected a non-empty opaque identifier
      or {module, function, args} tuple, got #{inspect(actor)}
      """
    end
  end

  defp validate_opt!({:visibility_policy, policy}) do
    validate_visibility_policy!(:visibility_policy, policy)
  end

  defp validate_opt!({:runtime_spec, spec}) do
    validate_runtime_spec!(:runtime_spec, spec, allow_mfa?: true)
  end

  defp validate_opt!({:runtime_specs, specs}) do
    validate_runtime_specs!(:runtime_specs, specs, allow_mfa?: true)
  end

  defp validate_opt!({:saved_specs, specs}) do
    validate_saved_specs!(:saved_specs, specs, allow_mfa?: true)
  end

  defp validate_opt!({:action_registry, registry}) do
    validate_action_registry!(:action_registry, registry, allow_mfa?: true)
  end

  defp validate_opt!(_option), do: :ok

  defp valid_control_actor_spec?(actor) when is_binary(actor), do: actor != ""
  defp valid_control_actor_spec?(actor) when is_map(actor), do: map_size(actor) > 0

  defp valid_control_actor_spec?(mfa) when is_tuple(mfa), do: valid_mfa_spec?(mfa)

  defp valid_control_actor_spec?(_actor), do: false

  defp valid_visibility_actor_spec?(actor) when is_binary(actor), do: actor != ""
  defp valid_visibility_actor_spec?(mfa) when is_tuple(mfa), do: valid_mfa_spec?(mfa)
  defp valid_visibility_actor_spec?(_actor), do: false

  defp valid_mfa_spec?({module, function, args}) do
    is_atom(module) and is_atom(function) and is_list(args)
  end

  defp valid_mfa_spec?(_spec), do: false

  defp validate_runtime_spec!(name, spec, opts \\ []) do
    allow_mfa? = Keyword.get(opts, :allow_mfa?, false)
    expected = "a map or struct#{mfa_suffix(allow_mfa?)}"

    unless is_nil(spec) or is_map(spec) or (allow_mfa? and valid_mfa_spec?(spec)) do
      raise ArgumentError, """
      invalid #{inspect(name)}, expected #{expected},
      got #{inspect(spec)}
      """
    end
  end

  defp validate_runtime_specs!(name, specs, opts \\ []) do
    allow_mfa? = Keyword.get(opts, :allow_mfa?, false)
    expected = "a keyword list or map#{mfa_suffix(allow_mfa?)}"

    unless is_nil(specs) or is_map(specs) or Keyword.keyword?(specs) or
             (allow_mfa? and valid_mfa_spec?(specs)) do
      raise ArgumentError, """
      invalid #{inspect(name)}, expected #{expected},
      got #{inspect(specs)}
      """
    end
  end

  defp validate_saved_specs!(name, specs, opts \\ []) do
    allow_mfa? = Keyword.get(opts, :allow_mfa?, false)
    expected = "a keyword list or map#{mfa_suffix(allow_mfa?)}"

    unless is_nil(specs) or is_map(specs) or Keyword.keyword?(specs) or
             (allow_mfa? and valid_mfa_spec?(specs)) do
      raise ArgumentError, """
      invalid #{inspect(name)}, expected #{expected},
      got #{inspect(specs)}
      """
    end
  end

  defp validate_action_registry!(name, registry, opts \\ []) do
    allow_mfa? = Keyword.get(opts, :allow_mfa?, false)
    expected = "a map or keyword list#{mfa_suffix(allow_mfa?)}"

    unless is_nil(registry) or is_map(registry) or Keyword.keyword?(registry) or
             (allow_mfa? and valid_mfa_spec?(registry)) do
      raise ArgumentError, """
      invalid #{inspect(name)}, expected #{expected},
      got #{inspect(registry)}
      """
    end
  end

  defp validate_visibility_policy!(name, policy) do
    unless valid_visibility_policy?(policy) do
      raise ArgumentError, """
      invalid #{inspect(name)}, expected :external, :operator, :auditor,
      a policy module, or {module, opts}, got #{inspect(policy)}
      """
    end
  end

  defp valid_visibility_policy?(policy) when policy in [:external, :operator, :auditor],
    do: true

  defp valid_visibility_policy?(policy) when is_atom(policy), do: not is_nil(policy)
  defp valid_visibility_policy?({module, _opts}) when is_atom(module), do: true
  defp valid_visibility_policy?(_policy), do: false

  defp mfa_suffix(true), do: ", or {module, function, args} tuple"
  defp mfa_suffix(false), do: ""

  defp runtime_session_options(%{} = runtime_options) do
    if Map.has_key?(runtime_options, :saved_specs) or
         Map.has_key?(runtime_options, :runtime_specs) do
      {
        Map.get(runtime_options, :saved_specs),
        Map.get(runtime_options, :runtime_specs),
        Map.get(runtime_options, :visibility_actor),
        Map.get(runtime_options, :visibility_policy, :operator)
      }
    else
      {nil, runtime_options, nil, :operator}
    end
  end

  defp runtime_session_options(runtime_specs), do: {nil, runtime_specs, nil, :operator}

  defp resolve_control_actor(conn, {module, function, args}) do
    conn
    |> then(&apply(module, function, [&1 | args]))
    |> normalize_control_actor()
  end

  defp resolve_control_actor(_conn, actor), do: normalize_control_actor(actor)

  defp resolve_visibility_actor(_conn, nil, control_actor) do
    control_actor
    |> control_actor_id()
    |> normalize_visibility_actor!()
  end

  defp resolve_visibility_actor(conn, {module, function, args}, _control_actor) do
    conn
    |> then(&apply(module, function, [&1 | args]))
    |> normalize_visibility_actor!()
  end

  defp resolve_visibility_actor(_conn, actor, _control_actor) do
    normalize_visibility_actor!(actor)
  end

  defp resolve_session_value(conn, {module, function, args}) do
    apply(module, function, [conn | args])
  end

  defp resolve_session_value(_conn, value), do: value

  defp normalize_control_actor(actor) when is_binary(actor) and actor != "", do: actor
  defp normalize_control_actor(actor) when is_map(actor) and map_size(actor) > 0, do: actor
  defp normalize_control_actor(_actor), do: @default_control_actor

  defp control_actor_id(actor) when is_binary(actor), do: actor

  defp control_actor_id(actor) when is_map(actor) do
    Jizoku.MapField.get(actor, :id, @default_control_actor["id"])
  end

  defp normalize_visibility_actor!(actor) when is_binary(actor) and actor != "", do: actor

  defp normalize_visibility_actor!(actor) do
    raise ArgumentError,
          "visibility_actor callback must return a non-empty opaque identifier, got: #{inspect(actor)}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
