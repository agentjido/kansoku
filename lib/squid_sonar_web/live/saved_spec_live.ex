defmodule SquidSonarWeb.SavedSpecLive do
  @moduledoc """
  Saved workflow spec draft detail surface.
  """

  use SquidSonarWeb, :live_view

  alias SquidSonar.Runs
  alias SquidSonar.SavedSpecs
  alias SquidSonar.ValidationErrors

  @impl Phoenix.LiveView
  def mount(%{"key" => key}, _session, socket) do
    socket =
      socket
      |> assign_new(:prefix, fn -> "" end)
      |> assign_new(:saved_specs, fn -> nil end)
      |> assign_new(:action_registry, fn -> nil end)
      |> assign(:page_title, "Saved workflow spec")
      |> assign(:theme, :system)
      |> assign(:saved_spec_start_error, nil)
      |> assign_saved_spec(key)

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, :theme, normalize_theme(theme))}
  end

  @impl Phoenix.LiveView
  def handle_event("start_saved_spec", %{"saved_spec_start" => params}, socket) do
    saved_spec = socket.assigns.saved_spec
    payload_json = Map.get(params, "payload_json", socket.assigns.saved_spec_payload_json)

    with %{startable?: true, spec: spec} <- saved_spec,
         {:ok, payload} <- decode_payload(payload_json),
         {:ok, run} <-
           Runs.start_spec(spec, payload, action_registry: socket.assigns.action_registry) do
      {:noreply,
       socket
       |> assign(:saved_spec_start_error, nil)
       |> push_navigate(to: "#{socket.assigns.prefix}/runs/#{run.run_id}")}
    else
      nil ->
        {:noreply, assign(socket, :saved_spec_start_error, "Saved workflow spec was not found.")}

      %{startable?: false} ->
        {:noreply,
         assign(socket, :saved_spec_start_error, "Saved workflow spec is not approved.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:saved_spec_payload_json, safe_payload_json(socket, reason))
         |> assign(:saved_spec_start_error, format_start_error(reason))}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main
      id="squid-sonar-saved-spec-page"
      phx-hook="SquidSonarTheme"
      class={["squid-sonar-shell", "squid-sonar-theme-#{@theme}"]}
    >
      <header class="squid-sonar-topbar">
        <.link navigate={@prefix <> "/"} class="squid-sonar-brand squid-sonar-brand-link">
          <div>
            <p class="squid-sonar-eyebrow">Saved workflow spec</p>
            <h1>SquidSonar</h1>
          </div>
        </.link>
        <div class="squid-sonar-topbar-actions">
          <.theme_switcher theme={@theme} />
        </div>
      </header>

      <div class="squid-sonar-content">
        <%= if @saved_spec do %>
          <section class="squid-sonar-saved-spec-detail">
            <header class="squid-sonar-saved-spec-hero">
              <div>
                <p class="squid-sonar-eyebrow">Host-owned draft</p>
                <h2>{@saved_spec.title}</h2>
                <p :if={@saved_spec.description}>{@saved_spec.description}</p>
              </div>
              <div class="squid-sonar-saved-spec-badges">
                <span class="squid-sonar-saved-spec-status">{@saved_spec.status_label}</span>
                <span class={[
                  "squid-sonar-saved-spec-validation",
                  @saved_spec.validation.status == :invalid && "is-invalid"
                ]}>
                  {validation_label(@saved_spec.validation)}
                </span>
              </div>
            </header>

            <div :if={@saved_spec_start_error} class="squid-sonar-alert" role="alert">
              <h2>Workflow start failed</h2>
              <p>{@saved_spec_start_error}</p>
            </div>

            <.validation_panel validation={@saved_spec.validation} />
            <.start_panel
              saved_spec={@saved_spec}
              payload_json={@saved_spec_payload_json}
              start_error={@saved_spec_start_error}
            />

            <section class="squid-sonar-saved-spec-grid">
              <.graph_panel preview={@saved_spec.preview} />
              <.diff_panel diff={@saved_spec.diff} />
              <.raw_panel title="Raw editor JSON" value={@saved_spec.editor_json} />
              <.raw_panel :if={@saved_spec.spec} title="Raw runtime spec" value={@saved_spec.spec} />
            </section>
          </section>
        <% else %>
          <section class="squid-sonar-empty-state">
            <h2>Saved workflow spec not found</h2>
            <p>The host application did not provide a saved draft for this key.</p>
          </section>
        <% end %>
      </div>
    </main>
    """
  end

  defp assign_saved_spec(socket, key) do
    case SavedSpecs.get(socket.assigns.saved_specs, key, socket.assigns.action_registry) do
      {:ok, saved_spec} ->
        assign(socket,
          saved_spec_key: key,
          saved_spec: saved_spec,
          saved_spec_payload_json: SavedSpecs.payload_json(saved_spec)
        )

      {:error, :not_found} ->
        assign(socket,
          saved_spec_key: key,
          saved_spec: nil,
          saved_spec_payload_json: Jason.encode!(%{}, pretty: true)
        )
    end
  end

  defp validation_panel(assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Validation</p>
          <h3>Status</h3>
        </div>
      </div>

      <p :if={@validation.status == :valid}>Valid</p>

      <ul :if={@validation.status == :invalid} class="squid-sonar-validation-errors">
        <li :for={error <- @validation.errors}>
          <strong>{ValidationErrors.format_path(Map.get(error, :path, []))}</strong>
          <span>{Map.get(error, :message, "workflow editor spec is invalid")}</span>
        </li>
      </ul>
    </section>
    """
  end

  defp start_panel(%{saved_spec: %{startable?: false}} = assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Activation</p>
          <h3>Start run</h3>
        </div>
      </div>
      <p>Only host-approved valid specs with an executable runtime spec can start runs.</p>
    </section>
    """
  end

  defp start_panel(assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Activation</p>
          <h3>Start run</h3>
        </div>
      </div>

      <form class="squid-sonar-runtime-spec-form" phx-submit="start_saved_spec">
        <label class="squid-sonar-runtime-spec-field">
          <span>Payload JSON</span>
          <textarea
            name="saved_spec_start[payload_json]"
            spellcheck="false"
            autocomplete="off"
          >{@payload_json}</textarea>
        </label>

        <button class="squid-sonar-control-button squid-sonar-control-button-primary" type="submit">
          Start run
        </button>
      </form>
    </section>
    """
  end

  defp graph_panel(assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Preview</p>
          <h3>Graph preview</h3>
        </div>
      </div>

      <%= case @preview do %>
        <% {:ok, graph} -> %>
          <div class="squid-sonar-graph-preview">
            <p>{length(Map.get(graph, "nodes", []))} nodes</p>
            <p>{length(Map.get(graph, "edges", []))} edges</p>
          </div>
          <pre class="squid-sonar-json-block">{json_pretty(graph)}</pre>
        <% {:error, reason} -> %>
          <p>Graph preview unavailable.</p>
          <p>{format_start_error(reason)}</p>
        <% nil -> %>
          <p>Graph preview unavailable.</p>
      <% end %>
    </section>
    """
  end

  defp diff_panel(%{diff: nil} = assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Source comparison</p>
          <h3>Draft diff</h3>
        </div>
      </div>
      <p>No source spec was provided by the host application.</p>
    </section>
    """
  end

  defp diff_panel(assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Source comparison</p>
          <h3>Draft diff</h3>
        </div>
      </div>

      <%= case @diff do %>
        <% {:ok, diff} -> %>
          <pre class="squid-sonar-json-block">{json_pretty(diff)}</pre>
        <% {:error, reason} -> %>
          <p>Draft diff unavailable.</p>
          <p>{format_start_error(reason)}</p>
      <% end %>
    </section>
    """
  end

  defp raw_panel(assigns) do
    ~H"""
    <section class="squid-sonar-saved-spec-section">
      <div class="squid-sonar-panel-heading">
        <div>
          <p class="squid-sonar-eyebrow">Inspection</p>
          <h3>{@title}</h3>
        </div>
      </div>
      <pre class="squid-sonar-json-block">{json_pretty(@value)}</pre>
    </section>
    """
  end

  defp decode_payload(payload_json) do
    case Jason.decode(payload_json) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _value} -> {:error, {:invalid_payload_json, :expected_object}}
      {:error, _error} -> {:error, :invalid_payload_json}
    end
  end

  defp safe_payload_json(socket, :invalid_payload_json),
    do: SavedSpecs.payload_json(socket.assigns.saved_spec)

  defp safe_payload_json(socket, {:invalid_payload_json, _reason}) do
    SavedSpecs.payload_json(socket.assigns.saved_spec)
  end

  defp safe_payload_json(socket, _reason), do: socket.assigns.saved_spec_payload_json

  defp validation_label(%{status: :valid}), do: "Valid"
  defp validation_label(%{status: :invalid}), do: "Invalid"

  defp normalize_theme("system"), do: :system
  defp normalize_theme("light"), do: :light
  defp normalize_theme("dark"), do: :dark
  defp normalize_theme(_theme), do: :system

  defp format_start_error(:invalid_payload_json), do: "Payload JSON is invalid."

  defp format_start_error({:invalid_payload_json, :expected_object}) do
    "Payload JSON must decode to an object."
  end

  defp format_start_error({:invalid_workflow_spec, errors}), do: ValidationErrors.format(errors)

  defp format_start_error({:invalid_workflow_editor_spec, errors}) do
    ValidationErrors.format(errors)
  end

  defp format_start_error(_reason), do: "Workflow start failed."

  defp json_pretty(value) do
    case Jason.encode(value, pretty: true) do
      {:ok, json} -> json
      {:error, _error} -> inspect(value, pretty: true)
    end
  end
end
