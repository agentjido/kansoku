defmodule SquidSonarWeb.SettingsLive do
  @moduledoc "Read-only, safely projected SquidSonar runtime settings."

  use SquidSonarWeb, :live_view

  alias SquidSonar.RuntimeSettings

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    projection = RuntimeSettings.project(socket.assigns)

    {:ok,
     socket
     |> assign_new(:prefix, fn -> "" end)
     |> assign(:page_title, "SquidSonar Settings")
     |> assign(:theme, :system)
     |> assign(:settings, projection)
     |> assign(:settings_json, RuntimeSettings.json(projection))}
  end

  @impl Phoenix.LiveView
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, :theme, normalize_theme(theme))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main
      id="squid-sonar-settings"
      phx-hook="SquidSonarTheme"
      class={["squid-sonar-shell", "squid-sonar-theme-#{@theme}"]}
    >
      <header class="squid-sonar-topbar">
        <.link navigate={@prefix <> "/"} class="squid-sonar-brand squid-sonar-brand-link">
          <div>
            <p class="squid-sonar-eyebrow">Runtime settings</p>
            <h1>SquidSonar</h1>
          </div>
        </.link>
        <div class="squid-sonar-topbar-actions">
          <.operator_nav prefix={@prefix} current={:settings} />
          <.theme_switcher theme={@theme} />
        </div>
      </header>

      <div class="squid-sonar-content squid-sonar-settings-content">
        <header class="squid-sonar-settings-heading">
          <div>
            <span class="squid-sonar-section-label">Safe runtime projection</span>
            <h2>Settings</h2>
            <p>
              Read-only integration metadata. Sensitive host configuration is intentionally omitted.
            </p>
          </div>
        </header>

        <section class="squid-sonar-settings-grid" aria-label="Runtime settings">
          <.setting label="SquidSonar" value={@settings.squid_sonar_version} />
          <.setting label="Squidie" value={@settings.squidie_version} />
          <.setting label="Integration status" value={@settings.integration_status} />
          <.setting label="Transport" value={@settings.transport} />
          <.setting label="Visibility" value={@settings.visibility} />
          <.setting label="Control access" value={@settings.control_access} />
          <.setting label="Runtime specs" value={catalog_label(@settings.runtime_specs_count)} />
          <.setting label="Saved specs" value={catalog_label(@settings.saved_specs_count)} />
          <.setting
            label="Action registry"
            value={configured_label(@settings.action_registry_configured)}
          />
        </section>

        <section class="squid-sonar-panel squid-sonar-settings-json-panel">
          <.panel_heading
            title="Safe JSON"
            description="Copy this allowlisted projection when troubleshooting an integration."
          >
            <:actions>
              <.copy_button id="copy-runtime-settings" target_id="runtime-settings-json" />
            </:actions>
          </.panel_heading>
          <pre id="runtime-settings-json" class="squid-sonar-workflow-raw-json"><code>{@settings_json}</code></pre>
        </section>
      </div>
    </main>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp setting(assigns) do
    ~H"""
    <article class="squid-sonar-setting">
      <span>{@label}</span>
      <strong>{@value}</strong>
    </article>
    """
  end

  defp catalog_label(0), do: "Not configured"
  defp catalog_label(1), do: "1 configured"
  defp catalog_label(count), do: "#{count} configured"
  defp configured_label(true), do: "Configured"
  defp configured_label(false), do: "Not configured"

  defp normalize_theme("system"), do: :system
  defp normalize_theme("light"), do: :light
  defp normalize_theme("dark"), do: :dark
  defp normalize_theme(_theme), do: :system
end
