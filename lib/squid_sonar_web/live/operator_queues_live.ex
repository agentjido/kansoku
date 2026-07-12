defmodule SquidSonarWeb.OperatorQueuesLive do
  @moduledoc """
  Read-only operator queues for manual boundaries and declared schedules.
  """

  use SquidSonarWeb, :live_view

  alias SquidSonar.OperatorQueues

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:prefix, Map.get(socket.assigns, :prefix, ""))
      |> assign(:runtime_specs, Map.get(socket.assigns, :runtime_specs))
      |> assign(:runtime_spec, Map.get(socket.assigns, :runtime_spec))
      |> assign(:visibility_actor, Map.get(socket.assigns, :visibility_actor, %{}))
      |> assign(:visibility_policy, Map.get(socket.assigns, :visibility_policy, :operator))
      |> assign(:page_title, "SquidSonar Operator Queues")
      |> assign(:theme, :system)
      |> assign_schedules()
      |> stream(:manual_actions, [], dom_id: &manual_action_dom_id/1)
      |> stream_manual_actions()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket) do
    {:noreply, stream_manual_actions(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, :theme, normalize_theme(theme))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main
      id="squid-sonar-operator-queues"
      phx-hook="SquidSonarTheme"
      class={["squid-sonar-shell", "squid-sonar-theme-#{@theme}"]}
    >
      <header class="squid-sonar-topbar">
        <.link navigate={@prefix <> "/"} class="squid-sonar-brand squid-sonar-brand-link">
          <div>
            <p class="squid-sonar-eyebrow">Operator queues</p>
            <h1>SquidSonar</h1>
          </div>
        </.link>
        <div class="squid-sonar-topbar-actions">
          <.operator_nav prefix={@prefix} current={:queues} />
          <.theme_switcher theme={@theme} />
        </div>
      </header>

      <div class="squid-sonar-content squid-sonar-queue-content">
        <header class="squid-sonar-queue-page-heading">
          <div>
            <span class="squid-sonar-section-label">Human attention</span>
            <h2>Operator queues</h2>
            <p>Review workflow boundaries that need input and declared recurring workflows.</p>
          </div>
          <button
            type="button"
            phx-click="refresh"
            class="squid-sonar-control-button squid-sonar-control-button-secondary"
          >
            Refresh queues
          </button>
        </header>

        <%= cond do %>
          <% @manual_actions.loading -> %>
            <section class="squid-sonar-panel squid-sonar-queue-loading" aria-live="polite">
              <p>Loading operator queues…</p>
            </section>
          <% @manual_actions.ok? -> %>
            <.manual_actions_panel streams={@streams} prefix={@prefix} />
            <.schedules_panel schedules={@schedules} />
          <% true -> %>
            <section class="squid-sonar-alert" role="alert">
              <h2>Unable to load operator queues</h2>
              <p>Check the host application's Squidie configuration and logs.</p>
            </section>
            <.schedules_panel schedules={@schedules} />
        <% end %>
      </div>
    </main>
    """
  end

  attr :streams, :map, required: true
  attr :prefix, :string, required: true

  defp manual_actions_panel(assigns) do
    ~H"""
    <section id="manual-actions" class="squid-sonar-panel squid-sonar-queue-panel">
      <div class="squid-sonar-panel-heading">
        <div class="squid-sonar-panel-title">
          <h2>Manual actions</h2>
          <p>Paused runs waiting for approval or an explicit resume decision.</p>
        </div>
      </div>

      <div class="squid-sonar-table-wrap">
        <table class="squid-sonar-table squid-sonar-queue-table">
          <caption class="squid-sonar-visually-hidden">Runs waiting for manual action</caption>
          <thead>
            <tr>
              <th scope="col">Workflow</th>
              <th scope="col">Queue</th>
              <th scope="col">Boundary</th>
              <th scope="col">Waiting</th>
              <th scope="col">Last event</th>
            </tr>
          </thead>
          <tbody id="manual-action-rows" phx-update="stream">
            <tr id="manual-actions-empty" class="squid-sonar-stream-empty">
              <td colspan="5">No runs are waiting for manual action.</td>
            </tr>
            <tr :for={{dom_id, action} <- @streams.manual_actions} id={dom_id}>
              <td>
                <.link
                  id={"manual-action-link-#{action.run_id}"}
                  navigate={"#{@prefix}/runs/#{action.run_id}"}
                  class="squid-sonar-run-link"
                >
                  <span class="squid-sonar-primary">{format_value(action.workflow)}</span>
                  <span class="squid-sonar-secondary">{action.run_id}</span>
                </.link>
              </td>
              <td>{action.queue}</td>
              <td>
                <span class="squid-sonar-primary">{format_value(action.step)}</span>
                <span class="squid-sonar-secondary">{format_value(action.kind)}</span>
              </td>
              <td>{format_duration(action.waiting_duration_seconds)}</td>
              <td>{action.last_event_summary}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :schedules, :list, required: true

  defp schedules_panel(assigns) do
    ~H"""
    <section id="schedules" class="squid-sonar-panel squid-sonar-queue-panel">
      <div class="squid-sonar-panel-heading">
        <div class="squid-sonar-panel-title">
          <h2>Schedules</h2>
          <p>Recurring triggers declared by workflows approved for this operator surface.</p>
        </div>
      </div>

      <%= if @schedules == [] do %>
        <div class="squid-sonar-empty">
          <h3>No schedules are configured for this operator surface.</h3>
        </div>
      <% else %>
        <div class="squid-sonar-table-wrap">
          <table class="squid-sonar-table squid-sonar-queue-table">
            <caption class="squid-sonar-visually-hidden">
              Declared recurring workflow triggers
            </caption>
            <thead>
              <tr>
                <th scope="col">Workflow</th>
                <th scope="col">Trigger</th>
                <th scope="col">Schedule</th>
                <th scope="col">Timezone</th>
                <th scope="col">Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={schedule <- @schedules}>
                <td>{format_value(schedule.workflow)}</td>
                <td>{format_value(schedule.trigger)}</td>
                <td><code>{schedule.expression}</code></td>
                <td>{schedule.timezone}</td>
                <td><span class="squid-sonar-schedule-status">Host-owned</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end

  defp assign_schedules(socket) do
    runtime_specs = socket.assigns.runtime_specs || socket.assigns.runtime_spec
    assign(socket, :schedules, OperatorQueues.list_schedules(runtime_specs))
  end

  defp stream_manual_actions(socket) do
    visibility_actor = socket.assigns.visibility_actor
    visibility_policy = socket.assigns.visibility_policy

    stream_async(
      socket,
      :manual_actions,
      fn ->
        case OperatorQueues.list_manual_actions(
               visibility_actor: visibility_actor,
               visibility_policy: visibility_policy
             ) do
          {:ok, manual_actions} -> {:ok, manual_actions}
          {:error, _reason} = error -> error
        end
      end,
      reset: true
    )
  end

  defp manual_action_dom_id(action) do
    "manual-action-#{action.run_id}"
  end

  defp format_duration(nil), do: "Unknown"
  defp format_duration(seconds) when seconds < 60, do: "Less than a minute"
  defp format_duration(seconds) when seconds < 3_600, do: duration(seconds, 60, "minute")
  defp format_duration(seconds), do: duration(seconds, 3_600, "hour")

  defp duration(seconds, divisor, unit) do
    count = div(seconds, divisor)
    suffix = if count == 1, do: unit, else: "#{unit}s"
    "#{count} #{suffix}"
  end

  defp format_value(nil), do: "Unknown"

  defp format_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp format_value(value), do: to_string(value)

  defp normalize_theme("system"), do: :system
  defp normalize_theme("light"), do: :light
  defp normalize_theme("dark"), do: :dark
  defp normalize_theme(_theme), do: :system
end
