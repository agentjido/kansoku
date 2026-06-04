defmodule SquidSonarWeb.PageLive do
  @moduledoc """
  Live dashboard for browsing recent Squid Mesh runs.
  """

  use SquidSonarWeb, :live_view

  alias SquidSonar.Dashboard

  @dashboard_refresh_interval_ms 2_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_new(:prefix, fn -> "" end)
      |> assign(:page_title, "SquidSonar Runtime")
      |> assign(:theme, :system)
      |> assign_dashboard()
      |> schedule_dashboard_refresh()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket) do
    dashboard = socket.assigns.dashboard

    {:noreply,
     assign_dashboard(socket,
       filters: dashboard.filters,
       page: dashboard.page,
       page_size: dashboard.page_size
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", params, socket) do
    {:noreply,
     assign_dashboard(socket,
       filters: Map.get(params, "filters", %{}),
       page_size: Map.get(params, "page_size"),
       page: 1
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("paginate", %{"page" => page} = params, socket) do
    dashboard = socket.assigns.dashboard

    {:noreply,
     assign_dashboard(socket,
       filters: dashboard.filters,
       page_size:
         Map.get(params, "page_size") || Map.get(params, "page-size") || dashboard.page_size,
       page: page
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, :theme, normalize_theme(theme))}
  end

  @impl Phoenix.LiveView
  def handle_info(:refresh_dashboard, socket) do
    dashboard = socket.assigns.dashboard

    socket =
      assign_dashboard(socket,
        filters: dashboard.filters,
        page: dashboard.page,
        page_size: dashboard.page_size
      )

    {:noreply, schedule_dashboard_refresh(socket)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main
      id="squid-sonar-page"
      phx-hook="SquidSonarTheme"
      class={["squid-sonar-shell", "squid-sonar-theme-#{@theme}"]}
    >
      <header class="squid-sonar-topbar">
        <.link navigate={@prefix <> "/"} class="squid-sonar-brand squid-sonar-brand-link">
          <div>
            <p class="squid-sonar-eyebrow">Runtime dashboard</p>
            <h1>SquidSonar</h1>
          </div>
        </.link>
        <div class="squid-sonar-topbar-actions">
          <.theme_switcher theme={@theme} />
        </div>
      </header>

      <%= if @dashboard.load_error do %>
        <.dashboard_error error={@dashboard.load_error} />
      <% else %>
        <div class="squid-sonar-content">
          <input
            id="squid-sonar-filter-toggle"
            class="squid-sonar-filter-toggle-input"
            type="checkbox"
          />

          <form phx-change="filter" phx-submit="filter">
            <label class="squid-sonar-filter-toggle" for="squid-sonar-filter-toggle">
              <span class="squid-sonar-filter-toggle-icon" aria-hidden="true">
                <span></span>
                <span></span>
                <span></span>
              </span>
              <span>Filters</span>
            </label>

            <section class="squid-sonar-workspace">
              <aside class="squid-sonar-sidebar" aria-label="Status inventory">
                <div class="squid-sonar-sidebar-heading">
                  <h2>Status</h2>
                </div>
                <.status_nav_item
                  status={:all}
                  count={@dashboard.loaded_count}
                  active={@dashboard.filters.status == :all}
                />
                <.status_nav_item
                  :for={status <- @dashboard.statuses}
                  status={status}
                  count={Map.fetch!(@dashboard.status_counts, status)}
                  active={@dashboard.filters.status == status}
                />
              </aside>

              <div class="squid-sonar-main-column">
                <.runs_panel dashboard={@dashboard} prefix={@prefix} />
              </div>
            </section>
          </form>
        </div>
      <% end %>
    </main>
    """
  end

  defp assign_dashboard(socket, opts \\ []) do
    assign(socket, :dashboard, Dashboard.load(opts))
  end

  defp schedule_dashboard_refresh(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_dashboard, @dashboard_refresh_interval_ms)
    end

    socket
  end

  defp normalize_theme("system"), do: :system
  defp normalize_theme("light"), do: :light
  defp normalize_theme("dark"), do: :dark
  defp normalize_theme(_theme), do: :system
end
