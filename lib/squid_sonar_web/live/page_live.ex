defmodule SquidSonarWeb.PageLive do
  @moduledoc """
  Live dashboard for browsing recent Squid Mesh runs.
  """

  use SquidSonarWeb, :live_view

  alias SquidSonar.Dashboard
  alias SquidSonar.Runs

  @dashboard_refresh_interval_ms 2_000
  @default_payload_json "{\n}"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_new(:prefix, fn -> "" end)
      |> assign_new(:runtime_spec, fn -> nil end)
      |> assign_new(:runtime_specs, fn -> nil end)
      |> assign_new(:action_registry, fn -> nil end)
      |> assign(:page_title, "SquidSonar Runtime")
      |> assign(:theme, :system)
      |> assign_runtime_spec_start()
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
  def handle_event("open_runtime_spec_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:runtime_spec_drawer_open?, true)
     |> assign(:runtime_spec_start_error, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("close_runtime_spec_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:runtime_spec_drawer_open?, false)
     |> assign(:runtime_spec_start_error, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("select_runtime_spec", %{"runtime_spec_start" => params}, socket) do
    selected_key = Map.get(params, "workflow", socket.assigns.selected_runtime_spec_key)

    case find_runtime_spec_entry(socket.assigns.runtime_spec_catalog, selected_key) do
      {:ok, entry} ->
        payload_json =
          if entry.key == socket.assigns.selected_runtime_spec_key do
            Map.get(params, "payload_json", socket.assigns.runtime_spec_payload_json)
          else
            runtime_spec_payload_json(entry.spec)
          end

        {:noreply,
         socket
         |> assign(:selected_runtime_spec_key, entry.key)
         |> assign(:runtime_spec_payload_json, payload_json)
         |> assign(:runtime_spec_start_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :runtime_spec_start_error, format_start_error(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("start_runtime_spec", %{"runtime_spec_start" => params}, socket) do
    selected_key = Map.get(params, "workflow", socket.assigns.selected_runtime_spec_key)
    payload_json = Map.get(params, "payload_json", selected_runtime_spec_payload_json(socket))

    with {:ok, entry} <-
           find_runtime_spec_entry(socket.assigns.runtime_spec_catalog, selected_key),
         {:ok, payload} <- decode_payload(payload_json),
         {:ok, run} <-
           start_runtime_spec_entry(entry, payload, socket.assigns.action_registry) do
      {:noreply,
       socket
       |> assign(:selected_runtime_spec_key, entry.key)
       |> assign(:runtime_spec_start_error, nil)
       |> push_navigate(to: "#{socket.assigns.prefix}/runs/#{run.run_id}")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:runtime_spec_drawer_open?, true)
         |> assign(
           :runtime_spec_payload_json,
           safe_payload_json(selected_runtime_spec(socket), payload_json, reason)
         )
         |> assign(:runtime_spec_start_error, format_start_error(reason))}
    end
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
          <button
            :if={@runtime_spec_catalog != []}
            type="button"
            phx-click="open_runtime_spec_drawer"
            class="squid-sonar-control-button squid-sonar-control-button-secondary"
          >
            Start workflow
          </button>
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

      <.runtime_spec_drawer
        :if={@runtime_spec_drawer_open? and @runtime_spec_catalog != []}
        runtime_spec_catalog={@runtime_spec_catalog}
        selected_runtime_spec_key={@selected_runtime_spec_key}
        payload_json={@runtime_spec_payload_json}
        start_error={@runtime_spec_start_error}
      />
    </main>
    """
  end

  defp runtime_spec_drawer(assigns) do
    ~H"""
    <button
      class="squid-sonar-runtime-spec-backdrop"
      type="button"
      phx-click="close_runtime_spec_drawer"
      aria-label="Close workflow starter"
    >
    </button>

    <aside
      class="squid-sonar-runtime-spec-drawer"
      role="dialog"
      aria-modal="true"
      aria-labelledby="squid-sonar-runtime-spec-title"
    >
      <header class="squid-sonar-runtime-spec-drawer-header">
        <div>
          <p class="squid-sonar-eyebrow">Host-approved workflow</p>
          <h2 id="squid-sonar-runtime-spec-title">Start workflow</h2>
        </div>
        <button
          class="squid-sonar-runtime-spec-close"
          type="button"
          phx-click="close_runtime_spec_drawer"
          aria-label="Close workflow starter"
          title="Close workflow starter"
        >
          x
        </button>
      </header>

      <div class="squid-sonar-runtime-spec-drawer-body">
        <div :if={@start_error} class="squid-sonar-alert" role="alert">
          <h2>Workflow start failed</h2>
          <p>{@start_error}</p>
        </div>

        <form
          class="squid-sonar-runtime-spec-form"
          phx-change="select_runtime_spec"
          phx-submit="start_runtime_spec"
        >
          <label class="squid-sonar-runtime-spec-field">
            <span>Workflow</span>
            <select name="runtime_spec_start[workflow]">
              <option
                :for={entry <- @runtime_spec_catalog}
                value={entry.key}
                selected={entry.key == @selected_runtime_spec_key}
              >
                {entry.label}
              </option>
            </select>
          </label>

          <section class="squid-sonar-runtime-spec-summary" aria-label="Runtime spec boundary">
            <p>
              The host application provides the workflow catalog and action registry. Pick a
              configured workflow, then edit payload JSON for its inputs.
            </p>
          </section>

          <label class="squid-sonar-runtime-spec-field">
            <span>Payload JSON</span>
            <textarea
              name="runtime_spec_start[payload_json]"
              spellcheck="false"
              autocomplete="off"
            >{@payload_json}</textarea>
          </label>

          <div class="squid-sonar-control-buttons">
            <button
              class="squid-sonar-control-button squid-sonar-control-button-primary"
              type="submit"
            >
              Start run
            </button>
          </div>
        </form>
      </div>
    </aside>
    """
  end

  defp assign_runtime_spec_start(socket) do
    catalog = runtime_spec_catalog(socket.assigns.runtime_specs, socket.assigns.runtime_spec)
    selected_key = selected_runtime_spec_key(catalog)

    assign(socket,
      runtime_spec_catalog: catalog,
      selected_runtime_spec_key: selected_key,
      runtime_spec_drawer_open?: false,
      runtime_spec_payload_json: selected_runtime_spec_payload_json(catalog, selected_key),
      runtime_spec_start_error: nil
    )
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

  defp decode_payload(payload_json) do
    case Jason.decode(payload_json) do
      {:ok, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _value} ->
        {:error, {:invalid_payload_json, :expected_object}}

      {:error, _error} ->
        {:error, :invalid_payload_json}
    end
  end

  defp safe_payload_json(runtime_spec, _payload_json, :invalid_payload_json) do
    runtime_spec_payload_json(runtime_spec)
  end

  defp safe_payload_json(runtime_spec, _payload_json, {:invalid_payload_json, _reason}) do
    runtime_spec_payload_json(runtime_spec)
  end

  defp safe_payload_json(_runtime_spec, payload_json, _reason), do: payload_json

  defp selected_runtime_spec(socket) do
    case find_runtime_spec_entry(
           socket.assigns.runtime_spec_catalog,
           socket.assigns.selected_runtime_spec_key
         ) do
      {:ok, entry} -> entry.spec
      {:error, _reason} -> nil
    end
  end

  defp selected_runtime_spec_payload_json(socket) do
    selected_runtime_spec_payload_json(
      socket.assigns.runtime_spec_catalog,
      socket.assigns.selected_runtime_spec_key
    )
  end

  defp selected_runtime_spec_payload_json(catalog, selected_key) do
    case find_runtime_spec_entry(catalog, selected_key) do
      {:ok, entry} -> runtime_spec_payload_json(entry.spec)
      {:error, _reason} -> @default_payload_json
    end
  end

  defp runtime_spec_catalog(runtime_specs, runtime_spec) do
    runtime_specs
    |> runtime_spec_catalog_entries(runtime_spec)
    |> Enum.reject(&is_nil/1)
  end

  defp runtime_spec_catalog_entries(nil, nil), do: []

  defp runtime_spec_catalog_entries(nil, runtime_spec),
    do: [runtime_spec_catalog_entry(nil, runtime_spec)]

  defp runtime_spec_catalog_entries(runtime_specs, _runtime_spec) when is_map(runtime_specs) do
    Enum.map(runtime_specs, fn {key, spec} -> runtime_spec_catalog_entry(key, spec) end)
  end

  defp runtime_spec_catalog_entries(runtime_specs, _runtime_spec) when is_list(runtime_specs) do
    if Keyword.keyword?(runtime_specs) do
      Enum.map(runtime_specs, fn {key, spec} -> runtime_spec_catalog_entry(key, spec) end)
    else
      Enum.map(runtime_specs, &runtime_spec_catalog_entry(nil, &1))
    end
  end

  defp runtime_spec_catalog_entries(_runtime_specs, runtime_spec) do
    runtime_spec_catalog_entries(nil, runtime_spec)
  end

  defp runtime_spec_catalog_entry(_key, nil), do: nil

  defp runtime_spec_catalog_entry(key, workflow)
       when is_atom(workflow) and not is_nil(workflow) do
    spec = runtime_spec_catalog_spec(workflow)
    entry_key = key || runtime_spec_workflow_value(spec)

    %{
      key: to_string(entry_key),
      label: runtime_spec_workflow_label(spec),
      spec: spec,
      start: {:workflow, workflow}
    }
  end

  defp runtime_spec_catalog_entry(key, spec_or_workflow) do
    spec = runtime_spec_catalog_spec(spec_or_workflow)
    entry_key = key || runtime_spec_workflow_value(spec)

    %{
      key: to_string(entry_key),
      label: runtime_spec_workflow_label(spec),
      spec: spec,
      start: {:spec, spec}
    }
  end

  defp runtime_spec_catalog_spec(workflow) when is_atom(workflow) and not is_nil(workflow) do
    case Squidie.Workflow.to_spec(workflow) do
      {:ok, spec} -> spec
      {:error, _reason} -> %{workflow: workflow}
    end
  end

  defp runtime_spec_catalog_spec(spec), do: spec

  defp start_runtime_spec_entry(%{start: {:workflow, workflow}}, payload, _action_registry) do
    Runs.start_workflow(workflow, payload)
  end

  defp start_runtime_spec_entry(%{start: {:spec, spec}}, payload, action_registry) do
    Runs.start_spec(spec, payload, action_registry: action_registry)
  end

  defp selected_runtime_spec_key([entry | _entries]), do: entry.key
  defp selected_runtime_spec_key([]), do: nil

  defp find_runtime_spec_entry(catalog, selected_key) when is_binary(selected_key) do
    case Enum.find(catalog, &(&1.key == selected_key)) do
      nil -> {:error, :unknown_runtime_spec}
      entry -> {:ok, entry}
    end
  end

  defp find_runtime_spec_entry([entry | _entries], nil), do: {:ok, entry}
  defp find_runtime_spec_entry(_catalog, _selected_key), do: {:error, :unknown_runtime_spec}

  defp runtime_spec_payload_json(nil), do: @default_payload_json

  defp runtime_spec_payload_json(runtime_spec) do
    runtime_spec
    |> runtime_spec_field(:payload, "payload")
    |> sample_payload()
    |> Jason.encode!(pretty: true)
  end

  defp sample_payload(payload_fields) when is_list(payload_fields) do
    Enum.reduce(payload_fields, %{}, fn field, payload ->
      case runtime_spec_field(field, :name, "name") do
        nil ->
          payload

        name ->
          field_name = to_string(name)
          field_type = runtime_spec_field(field, :type, "type")
          Map.put(payload, field_name, sample_payload_value(field_name, field_type))
      end
    end)
  end

  defp sample_payload(_payload_fields), do: %{}

  defp sample_payload_value(_field_name, type) when type in [:integer, "integer"], do: 1
  defp sample_payload_value(_field_name, type) when type in [:float, "float"], do: 1.0
  defp sample_payload_value(_field_name, type) when type in [:boolean, "boolean"], do: true
  defp sample_payload_value(_field_name, type) when type in [:map, "map"], do: %{}
  defp sample_payload_value(_field_name, type) when type in [:list, "list"], do: []
  defp sample_payload_value(field_name, _type), do: "#{field_name}_example"

  defp runtime_spec_workflow_label(runtime_spec) do
    runtime_spec
    |> runtime_spec_field(:workflow, "workflow")
    |> workflow_to_label()
  end

  defp runtime_spec_workflow_value(runtime_spec) do
    runtime_spec
    |> runtime_spec_field(:workflow, "workflow")
    |> workflow_to_value()
  end

  defp runtime_spec_field(value, atom_key, string_key) when is_map(value) do
    cond do
      Map.has_key?(value, atom_key) -> Map.fetch!(value, atom_key)
      Map.has_key?(value, string_key) -> Map.fetch!(value, string_key)
      true -> nil
    end
  end

  defp runtime_spec_field(_value, _atom_key, _string_key), do: nil

  defp workflow_to_label(nil), do: "Configured workflow"

  defp workflow_to_label(workflow) when is_atom(workflow) do
    workflow
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  defp workflow_to_label(workflow) when is_binary(workflow), do: workflow
  defp workflow_to_label(workflow), do: inspect(workflow)

  defp workflow_to_value(nil), do: "configured_workflow"
  defp workflow_to_value(workflow) when is_atom(workflow), do: Atom.to_string(workflow)
  defp workflow_to_value(workflow) when is_binary(workflow), do: workflow
  defp workflow_to_value(workflow), do: inspect(workflow)

  defp format_start_error(:invalid_payload_json), do: "Payload JSON is invalid."

  defp format_start_error({:invalid_payload_json, :expected_object}) do
    "Payload JSON must decode to an object."
  end

  defp format_start_error({:invalid_workflow_spec, errors}), do: format_validation_errors(errors)

  defp format_start_error({:invalid_workflow_editor_spec, errors}),
    do: format_validation_errors(errors)

  defp format_start_error({:invalid_payload, :expected_map}), do: "Payload must be a JSON object."
  defp format_start_error(:unknown_runtime_spec), do: "Selected workflow is not configured."
  defp format_start_error(_reason), do: "Workflow start failed."

  defp format_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(&format_validation_error/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  defp format_validation_errors(_errors), do: "Runtime spec validation failed."

  defp format_validation_error(%{path: path, message: message}) when is_list(path) do
    "#{format_path(path)}: #{message}"
  end

  defp format_validation_error(%{message: message}) when is_binary(message), do: message
  defp format_validation_error(_error), do: ""

  defp format_path(path) do
    Enum.map_join(path, ".", &to_string/1)
  end

  defp normalize_theme("system"), do: :system
  defp normalize_theme("light"), do: :light
  defp normalize_theme("dark"), do: :dark
  defp normalize_theme(_theme), do: :system
end
