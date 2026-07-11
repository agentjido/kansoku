defmodule SquidSonarWeb.RunLive do
  @moduledoc """
  Live run detail page for inspecting and controlling a Squid Mesh run.
  """

  use SquidSonarWeb, :live_view

  alias SquidSonar.Runs

  @run_refresh_interval_ms 1_000
  @control_refresh_interval_ms 250
  @control_events ~w(cancel resume approve reject replay)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:prefix, Map.get(socket.assigns, :prefix, ""))
     |> assign(
       :control_actor,
       Map.get(socket.assigns, :control_actor, SquidSonar.Router.default_control_actor())
     )
     |> assign(:visibility_actor, Map.get(socket.assigns, :visibility_actor, "squid_sonar"))
     |> assign(:visibility_policy, Map.get(socket.assigns, :visibility_policy, :auditor))
     |> assign(:page_title, "SquidSonar Run")
     |> assign(:theme, :system)
     |> assign(:workflow_panel_view, :visual)}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => run_id}, _uri, socket) do
    {:noreply,
     socket
     |> assign_run(run_id)
     |> schedule_run_refresh()}
  end

  @impl Phoenix.LiveView
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, :theme, normalize_theme(theme))}
  end

  @impl Phoenix.LiveView
  def handle_event("clear_flash", _params, socket) do
    {:noreply, clear_run_flash(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("select_workflow_panel", %{"view" => view}, socket) do
    {:noreply, assign(socket, :workflow_panel_view, normalize_workflow_panel_view(view))}
  end

  @impl Phoenix.LiveView
  def handle_event("show_visual_workflow_panel", _params, socket) do
    {:noreply, assign(socket, :workflow_panel_view, :visual)}
  end

  @impl Phoenix.LiveView
  def handle_event("show_raw_workflow_panel", _params, socket) do
    {:noreply, assign(socket, :workflow_panel_view, :raw)}
  end

  @impl Phoenix.LiveView
  def handle_event(
        event,
        _params,
        %{assigns: %{detail: detail}} = socket
      )
      when event in @control_events and not is_map(detail) do
    {:noreply, put_run_flash(socket, :error, "Run controls are not authorized.")}
  end

  @impl Phoenix.LiveView
  def handle_event(
        event,
        _params,
        %{assigns: %{detail: %{controls_allowed?: false}}} = socket
      )
      when event in @control_events do
    {:noreply, put_run_flash(socket, :error, "Run controls are not authorized.")}
  end

  @impl Phoenix.LiveView
  def handle_event(
        event,
        %{"run-id" => requested_run_id},
        %{assigns: %{run_id: current_run_id}} = socket
      )
      when event in @control_events and requested_run_id != current_run_id do
    {:noreply, put_run_flash(socket, :error, "Run controls are not authorized.")}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel", %{"run-id" => run_id}, socket) do
    case Runs.cancel_run(run_id) do
      {:ok, _updated_run} ->
        {:noreply,
         socket
         |> put_run_flash(:info, "Run cancelled successfully")
         |> assign_run(run_id)
         |> schedule_control_refresh()}

      {:error, _reason} ->
        {:noreply, put_run_flash(socket, :error, "Failed to cancel run.")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("resume", %{"run-id" => run_id}, socket) do
    case Runs.resume_run(run_id, control_attrs(socket)) do
      {:ok, _updated_run} ->
        {:noreply,
         socket
         |> put_run_flash(:info, "Run resumed successfully")
         |> assign_run(run_id)
         |> schedule_control_refresh()}

      {:error, _reason} ->
        {:noreply, put_run_flash(socket, :error, "Failed to resume run.")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("approve", %{"run-id" => run_id}, socket) do
    case Runs.approve_run(run_id, control_attrs(socket)) do
      {:ok, _updated_run} ->
        {:noreply,
         socket
         |> put_run_flash(:info, "Run approved successfully")
         |> assign_run(run_id)
         |> schedule_control_refresh()}

      {:error, _reason} ->
        {:noreply, put_run_flash(socket, :error, "Failed to approve run.")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("reject", %{"run-id" => run_id}, socket) do
    case Runs.reject_run(run_id, control_attrs(socket)) do
      {:ok, _updated_run} ->
        {:noreply,
         socket
         |> put_run_flash(:info, "Run rejected successfully")
         |> assign_run(run_id)
         |> schedule_control_refresh()}

      {:error, _reason} ->
        {:noreply, put_run_flash(socket, :error, "Failed to reject run.")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("replay", %{"run-id" => run_id}, socket) do
    case Runs.replay_run(run_id) do
      {:ok, new_run} ->
        {:noreply,
         socket
         |> put_run_flash(:info, "Run replayed successfully")
         |> assign_run(new_run.run_id)
         |> schedule_control_refresh()
         |> push_patch(to: run_path(socket, new_run.run_id))}

      {:error, _reason} ->
        {:noreply, put_run_flash(socket, :error, "Failed to replay run.")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main
      id="squid-sonar-run"
      phx-hook="SquidSonarTheme"
      class={["squid-sonar-shell", "squid-sonar-theme-#{@theme}"]}
    >
      <header class="squid-sonar-topbar">
        <.link navigate={@prefix <> "/"} class="squid-sonar-brand squid-sonar-brand-link">
          <div>
            <p class="squid-sonar-eyebrow">Run detail</p>
            <h1>SquidSonar</h1>
          </div>
        </.link>
        <.theme_switcher theme={@theme} />
      </header>

      <.flash_messages flash={visible_flash(assigns)} />

      <div class="squid-sonar-content">
        <%= if @load_error do %>
          <.dashboard_error error={@load_error} />
        <% else %>
          <.run_detail
            detail={@detail}
            prefix={@prefix}
            workflow_panel_view={@workflow_panel_view}
          />
        <% end %>
      </div>
    </main>
    """
  end

  @impl Phoenix.LiveView
  def handle_info(:refresh_run, socket) do
    {:noreply,
     socket
     |> assign_run(socket.assigns.run_id)
     |> schedule_run_refresh()}
  end

  defp assign_run(socket, run_id) do
    case Runs.get_run(run_id,
           visibility_actor: socket.assigns.visibility_actor,
           visibility_policy: socket.assigns.visibility_policy,
           controls_allowed?: controls_allowed?(socket)
         ) do
      {:ok, detail} ->
        socket
        |> assign(:run_id, run_id)
        |> assign(:detail, detail)
        |> assign(:load_error, nil)

      {:error, reason} ->
        socket
        |> assign(:run_id, run_id)
        |> assign(:detail, nil)
        |> assign(:load_error, reason)
    end
  end

  defp schedule_control_refresh(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_run, @control_refresh_interval_ms)
    end

    socket
  end

  defp schedule_run_refresh(socket) do
    if connected?(socket) and refreshable_run?(socket) do
      Process.send_after(self(), :refresh_run, @run_refresh_interval_ms)
    end

    socket
  end

  defp refreshable_run?(%{assigns: %{detail: %{summary: %{terminal?: terminal?}}}}) do
    not terminal?
  end

  defp refreshable_run?(_socket), do: false

  defp put_run_flash(socket, kind, message) do
    if Map.has_key?(socket.assigns, :flash) do
      put_flash(socket, kind, message)
    else
      assign(socket, :control_flash, %{Atom.to_string(kind) => message})
    end
  end

  defp visible_flash(assigns) do
    Map.get(assigns, :flash, Map.get(assigns, :control_flash, %{}))
  end

  defp clear_run_flash(socket) do
    if Map.has_key?(socket.assigns, :flash) do
      clear_flash(socket)
    else
      assign(socket, :control_flash, %{})
    end
  end

  defp control_attrs(socket) do
    %{actor: Map.get(socket.assigns, :control_actor, SquidSonar.Router.default_control_actor())}
  end

  defp controls_allowed?(socket), do: socket.assigns.visibility_policy == :operator

  defp normalize_theme("system"), do: :system
  defp normalize_theme("light"), do: :light
  defp normalize_theme("dark"), do: :dark
  defp normalize_theme(_theme), do: :system

  defp normalize_workflow_panel_view("raw"), do: :raw
  defp normalize_workflow_panel_view(_view), do: :visual

  defp run_path(socket, run_id), do: "#{socket.assigns.prefix}/runs/#{run_id}"
end
