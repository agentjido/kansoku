defmodule SquidSonarWeb.Hooks do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Copies SquidSonar session values into LiveView assigns.
  """
  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:prefix, Map.fetch!(session, "prefix"))
      |> assign(:live_path, Map.fetch!(session, "live_path"))
      |> assign(:live_transport, Map.fetch!(session, "live_transport"))
      |> assign(
        :control_actor,
        Map.get(session, "control_actor", SquidSonar.Router.default_control_actor())
      )
      |> assign(:runtime_spec, Map.get(session, "runtime_spec"))
      |> assign(:runtime_specs, Map.get(session, "runtime_specs"))
      |> assign(:saved_specs, Map.get(session, "saved_specs"))
      |> assign(:action_registry, Map.get(session, "action_registry"))
      |> assign(:visibility_actor, Map.get(session, "visibility_actor", %{}))
      |> assign(:visibility_policy, Map.get(session, "visibility_policy", :operator))

    {:cont, socket}
  end
end
