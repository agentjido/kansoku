defmodule SquidSonarWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  alias SquidSonarWeb.WorkflowGraphLayout

  attr :prefix, :string, default: ""
  attr :current, :atom, required: true

  @spec operator_nav(map()) :: Phoenix.LiveView.Rendered.t()
  def operator_nav(assigns) do
    ~H"""
    <nav class="squid-sonar-operator-nav" aria-label="SquidSonar navigation">
      <.nav_link href={@prefix <> "/"} label="Recent runs" current={@current == :runs} />
      <.nav_link
        href={@prefix <> "/#workflow-runs"}
        label="Workflows"
        current={@current == :workflows}
      />
      <.nav_link href={@prefix <> "/queues"} label="Manual actions" current={@current == :queues} />
      <.nav_link href={@prefix <> "/settings"} label="Settings" current={@current == :settings} />
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :target_id, :string, required: true
  attr :label, :string, default: "Copy"
  attr :text, :string, default: nil

  @spec copy_button(map()) :: Phoenix.LiveView.Rendered.t()
  def copy_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="squid-sonar-copy-button"
      phx-hook="SquidSonarCopy"
      data-copy-target={@target_id}
      data-copy-label={@label}
      data-copy-text={@text || @label}
      title={@label}
      aria-label={@label}
    >
      {@text || @label}
    </button>
    """
  end

  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :level, :atom, values: [:h2, :h3], default: :h2
  attr :class, :any, default: nil
  slot :actions

  @spec panel_heading(map()) :: Phoenix.LiveView.Rendered.t()
  def panel_heading(assigns) do
    ~H"""
    <div class={["squid-sonar-panel-heading", @class]}>
      <div class="squid-sonar-section-heading-copy">
        <p :if={@eyebrow} class="squid-sonar-eyebrow">{@eyebrow}</p>
        <h2 :if={@level == :h2}>{@title}</h2>
        <h3 :if={@level == :h3}>{@title}</h3>
        <p :if={@description} class="squid-sonar-panel-heading-description">{@description}</p>
      </div>

      <div :if={@actions != []} class="squid-sonar-panel-tools">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :current, :boolean, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={["squid-sonar-operator-nav-link", @current && "is-active"]}
      aria-current={@current && "page"}
    >
      {@label}
    </.link>
    """
  end

  attr :status, :atom, required: true

  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def status_badge(assigns) do
    ~H"""
    <span class={["squid-sonar-badge", "squid-sonar-badge-#{@status}"]}>
      {@status}
    </span>
    """
  end

  attr :mode, :atom, required: true

  @spec graph_mode_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def graph_mode_badge(assigns) do
    ~H"""
    <span class={[
      "squid-sonar-badge",
      "squid-sonar-graph-mode-badge",
      "squid-sonar-graph-mode-badge-#{@mode}"
    ]}>
      {graph_mode_label(@mode)}
    </span>
    """
  end

  attr :flash, :map, required: true

  @spec flash_messages(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_messages(assigns) do
    assigns =
      assigns
      |> assign(:info, flash_message(assigns.flash, :info))
      |> assign(:error, flash_message(assigns.flash, :error))

    ~H"""
    <div
      :if={@info || @error}
      id="squid-sonar-flash"
      class="squid-sonar-flash-stack"
      role={if @error, do: "alert", else: "status"}
      phx-hook="SquidSonarFlash"
    >
      <div class={[
        "squid-sonar-flash",
        @info && "squid-sonar-flash-info",
        @error && "squid-sonar-flash-error"
      ]}>
        <span>{@info || @error}</span>
        <button
          class="squid-sonar-flash-close"
          type="button"
          phx-click="clear_flash"
          aria-label="Dismiss notification"
        >
          x
        </button>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :count, :integer, required: true
  attr :active, :boolean, default: false

  @spec status_nav_item(map()) :: Phoenix.LiveView.Rendered.t()
  def status_nav_item(assigns) do
    ~H"""
    <label class={["squid-sonar-nav-item", @active && "is-active"]}>
      <input type="radio" name="filters[status]" value={@status} checked={@active} />
      <span class="squid-sonar-nav-label">
        <span>{human_status(@status)}</span>
      </span>
      <strong>{@count}</strong>
    </label>
    """
  end

  attr :theme, :atom, required: true

  @spec theme_switcher(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_switcher(assigns) do
    ~H"""
    <div class="squid-sonar-theme-switcher" aria-label="Theme">
      <.theme_button theme={@theme} value={:system} label="Use system theme">
        <rect x="3" y="4" width="18" height="12" rx="2" />
        <path d="M8 20h8" />
        <path d="M12 16v4" />
      </.theme_button>
      <.theme_button theme={@theme} value={:light} label="Use light theme">
        <path d="M12 3v2" />
        <path d="M12 19v2" />
        <path d="m5.6 5.6 1.4 1.4" />
        <path d="m17 17 1.4 1.4" />
        <path d="M3 12h2" />
        <path d="M19 12h2" />
        <path d="m5.6 18.4 1.4-1.4" />
        <path d="m17 7 1.4-1.4" />
        <circle cx="12" cy="12" r="4" />
      </.theme_button>
      <.theme_button theme={@theme} value={:dark} label="Use dark theme">
        <path d="M20 14.4A7.8 7.8 0 0 1 9.6 4a8 8 0 1 0 10.4 10.4Z" />
      </.theme_button>
    </div>
    """
  end

  @doc """
  Renders the dashboard refresh button.
  """
  @spec refresh_button(map()) :: Phoenix.LiveView.Rendered.t()
  def refresh_button(assigns) do
    ~H"""
    <button
      class="squid-sonar-icon-button squid-sonar-refresh"
      type="button"
      phx-click="refresh"
      title="Refresh runs"
      aria-label="Refresh runs"
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M20 11a8.1 8.1 0 0 0-15.5-2" />
        <path d="M4 5v4h4" />
        <path d="M4 13a8.1 8.1 0 0 0 15.5 2" />
        <path d="M20 19v-4h-4" />
      </svg>
    </button>
    """
  end

  attr :theme, :atom, required: true
  attr :value, :atom, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp theme_button(assigns) do
    ~H"""
    <button
      class={["squid-sonar-icon-button", @theme == @value && "is-active"]}
      type="button"
      phx-click="set_theme"
      phx-value-theme={@value}
      data-squid-sonar-theme={@value}
      title={@label}
      aria-label={@label}
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        {render_slot(@inner_block)}
      </svg>
    </button>
    """
  end

  attr :error, :any, required: true

  @spec dashboard_error(map()) :: Phoenix.LiveView.Rendered.t()
  def dashboard_error(assigns) do
    ~H"""
    <section class="squid-sonar-alert" role="alert">
      <h2>Unable to load runs</h2>
      <p>Check the host application's Squidie configuration and logs.</p>
    </section>
    """
  end

  @doc """
  Renders the empty dashboard state.
  """
  @spec empty_runs(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_runs(assigns) do
    ~H"""
    <div class="squid-sonar-empty">
      <h3>No runs found</h3>
    </div>
    """
  end

  attr :dashboard, :map, required: true
  attr :prefix, :string, default: ""
  attr :advanced_filters_open?, :boolean, default: false
  attr :saved_specs_count, :integer, default: 0
  attr :saved_specs_open?, :boolean, default: false
  slot :saved_workflows

  @spec runs_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def runs_panel(assigns) do
    ~H"""
    <section class="squid-sonar-panel squid-sonar-runs-panel">
      <.panel_heading
        eyebrow="Recent execution activity across the host runtime."
        title="Workflow runs"
        class="squid-sonar-runs-panel-heading"
      >
        <:actions>
          <button
            :if={@saved_specs_count > 0}
            id="saved-workflows-toggle"
            type="button"
            class="squid-sonar-icon-button"
            phx-click="toggle_saved_specs"
            aria-expanded={to_string(@saved_specs_open?)}
            aria-controls="saved-workflows-panel"
            title="Saved workflows"
            aria-label="Saved workflows"
          >
            <svg
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M6 4.5A1.5 1.5 0 0 1 7.5 3h9A1.5 1.5 0 0 1 18 4.5V21l-6-4-6 4Z" />
            </svg>
          </button>
          <.refresh_button />
        </:actions>
      </.panel_heading>

      <div class="squid-sonar-panel-actions squid-sonar-runs-panel-filters">
        <div class="squid-sonar-filter-controls squid-sonar-filter-controls-primary">
          <label class="squid-sonar-search squid-sonar-search-query">
            <span>Search</span>
            <input
              type="search"
              name="filters[query]"
              value={@dashboard.filters.query}
              placeholder="Workflow, queue, status, run ID"
              phx-debounce="250"
            />
          </label>

          <label class="squid-sonar-search squid-sonar-search-prefix">
            <span>Run ID prefix</span>
            <input
              type="search"
              name="filters[run_id]"
              value={@dashboard.filters.run_id}
              placeholder="run-abc"
              maxlength="128"
              phx-debounce="250"
            />
          </label>

          <label class="squid-sonar-select-filter">
            <span>Workflow</span>
            <select name="filters[workflow]">
              <option value="">All workflows</option>
              <option
                :for={workflow <- @dashboard.workflows}
                value={workflow}
                selected={@dashboard.filters.workflow == workflow}
              >
                {format_workflow(workflow)}
              </option>
            </select>
          </label>

          <label class="squid-sonar-select-filter">
            <span>Queue</span>
            <select name="filters[queue]">
              <option value="">All queues</option>
              <option
                :for={queue <- @dashboard.queues}
                value={queue}
                selected={@dashboard.filters.queue == queue}
              >
                {queue}
              </option>
            </select>
          </label>
        </div>

        <div class="squid-sonar-filter-utility-row">
          <details
            class="squid-sonar-advanced-filters"
            open={@advanced_filters_open? or advanced_filters_active?(@dashboard.filters)}
          >
            <summary phx-click="toggle_advanced_filters">
              <span>Advanced filters</span>
              <span class="squid-sonar-advanced-filters-hint">Terminal, time, actions, deadline</span>
            </summary>

            <div class="squid-sonar-filter-controls squid-sonar-filter-controls-advanced">
              <label class="squid-sonar-select-filter">
                <span>Terminal</span>
                <select name="filters[terminal]">
                  <option value="all" selected={@dashboard.filters.terminal == :all}>
                    All terminal states
                  </option>
                  <option
                    :for={terminal <- @dashboard.terminal_statuses}
                    value={terminal}
                    selected={@dashboard.filters.terminal == terminal}
                  >
                    {human_status(terminal)}
                  </option>
                </select>
              </label>

              <label class="squid-sonar-select-filter">
                <span>Time window</span>
                <select name="filters[window]">
                  <option
                    :for={{value, label} <- time_window_options()}
                    value={value}
                    selected={@dashboard.filters.window == value}
                  >
                    {label}
                  </option>
                </select>
              </label>

              <label class="squid-sonar-select-filter">
                <span>Manual action</span>
                <select name="filters[manual]">
                  <option value="all" selected={@dashboard.filters.manual == :all}>All runs</option>
                  <option value="waiting" selected={@dashboard.filters.manual == :waiting}>
                    Waiting for action
                  </option>
                  <option value="none" selected={@dashboard.filters.manual == :none}>
                    No manual action
                  </option>
                </select>
              </label>

              <label class="squid-sonar-select-filter">
                <span>Deadline</span>
                <select name="filters[deadline]">
                  <option
                    :for={{value, label} <- deadline_filter_options()}
                    value={value}
                    selected={@dashboard.filters.deadline == value}
                  >
                    {label}
                  </option>
                </select>
              </label>
            </div>
          </details>

          <button
            id="reset-run-filters"
            type="button"
            class="squid-sonar-reset-filters"
            phx-click="reset_filters"
          >
            Reset filters
          </button>
        </div>
      </div>

      <div
        :if={@saved_specs_open? and @saved_workflows != []}
        class="squid-sonar-saved-workflows-slot"
      >
        {render_slot(@saved_workflows)}
      </div>

      <%= if @dashboard.runs == [] do %>
        <.empty_runs />
      <% else %>
        <.runs_table runs={@dashboard.runs} prefix={@prefix} />
        <.pagination
          page={@dashboard.page}
          total_pages={@dashboard.total_pages}
          filtered_count={@dashboard.filtered_count}
          loaded_at={@dashboard.loaded_at}
          page_size={@dashboard.page_size}
          page_sizes={@dashboard.page_sizes}
        />
      <% end %>
    </section>
    """
  end

  defp time_window_options do
    [
      {:all, "All time"},
      {:"1h", "Last hour"},
      {:"24h", "Last 24 hours"},
      {:"7d", "Last 7 days"},
      {:"30d", "Last 30 days"}
    ]
  end

  defp advanced_filters_active?(filters) do
    filters.terminal != :all or filters.window != :all or filters.manual != :all or
      filters.deadline != :all
  end

  attr :runs, :list, required: true
  attr :prefix, :string, default: ""

  @spec runs_table(map()) :: Phoenix.LiveView.Rendered.t()
  def runs_table(assigns) do
    ~H"""
    <div class="squid-sonar-table-wrap">
      <table class="squid-sonar-table squid-sonar-runs-table">
        <thead>
          <tr>
            <th>Workflow</th>
            <th>Queue</th>
            <th>Status</th>
            <th>Terminal</th>
            <th>Deadline</th>
            <th>Indexed</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={run <- @runs}>
            <td>
              <div class="squid-sonar-run-title">
                <.link navigate={run_path(@prefix, run.id)} class="squid-sonar-run-link">
                  <span id={"run-workflow-#{run.id}"} class="squid-sonar-primary">
                    {format_workflow(run.workflow)}
                  </span>
                  <span id={"run-id-#{run.id}"} class="squid-sonar-secondary">{run.id}</span>
                </.link>
                <div class="squid-sonar-copy-controls">
                  <.copy_button
                    id={"copy-run-workflow-#{run.id}"}
                    target_id={"run-workflow-#{run.id}"}
                    label="Copy name"
                    text="Name"
                  />
                  <.copy_button
                    id={"copy-run-id-#{run.id}"}
                    target_id={"run-id-#{run.id}"}
                    label="Copy ID"
                    text="ID"
                  />
                </div>
              </div>
            </td>
            <td>{format_value(run.queue)}</td>
            <td><.status_badge status={run.status} /></td>
            <td>{format_value(run.terminal_status)}</td>
            <td>
              <div class="squid-sonar-deadline-cell">
                <span class={[
                  "squid-sonar-deadline-badge",
                  "squid-sonar-deadline-badge-#{deadline_status(run.deadline)}"
                ]}>
                  {format_deadline_status(deadline_status(run.deadline))}
                </span>
                <span :if={deadline_step(run.deadline) != "None"} class="squid-sonar-deadline-meta">
                  {deadline_step(run.deadline)}
                </span>
              </div>
            </td>
            <td><.timestamp value={run.indexed_at} /></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :filtered_count, :integer, required: true
  attr :loaded_at, :any, required: true
  attr :page_size, :integer, required: true
  attr :page_sizes, :list, required: true

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    assigns =
      assigns
      |> assign(:previous_page, max(assigns.page - 1, 1))
      |> assign(:next_page, min(assigns.page + 1, assigns.total_pages))

    ~H"""
    <nav class="squid-sonar-pagination" aria-label="Runs pagination">
      <span class="squid-sonar-pagination-summary">
        <strong>Recent runs</strong>
        <span>{@filtered_count} matching</span>
        <span>Updated <.timestamp value={@loaded_at} /></span>
      </span>
      <div class="squid-sonar-pagination-controls">
        <label class="squid-sonar-page-size">
          <span>Page size</span>
          <select name="page_size">
            <option
              :for={page_size <- @page_sizes}
              value={page_size}
              selected={page_size == @page_size}
            >
              {page_size}
            </option>
          </select>
        </label>
        <button
          type="button"
          phx-click="paginate_previous"
          phx-value-page={@previous_page}
          disabled={@page <= 1}
        >
          Previous
        </button>
        <strong>{@page} / {@total_pages}</strong>
        <button
          type="button"
          phx-click="paginate_next"
          phx-value-page={@next_page}
          disabled={@page >= @total_pages}
        >
          Next
        </button>
      </div>
    </nav>
    """
  end

  attr :detail, :map, required: true
  attr :prefix, :string, default: ""
  attr :workflow_panel_view, :atom, default: :visual

  @spec run_detail(map()) :: Phoenix.LiveView.Rendered.t()
  def run_detail(assigns) do
    ~H"""
    <section class="squid-sonar-detail">
      <header class="squid-sonar-detail-header">
        <div>
          <.link navigate={@prefix <> "/"} class="squid-sonar-back-link">Back to runs</.link>
          <span class="squid-sonar-section-label">Run summary</span>
          <div class="squid-sonar-copy-row">
            <h2 id="run-detail-workflow">{format_workflow(@detail.summary.workflow)}</h2>
            <.copy_button
              id="copy-run-detail-workflow"
              target_id="run-detail-workflow"
              label="Copy workflow"
            />
          </div>
          <div class="squid-sonar-copy-row">
            <p id="run-detail-id">{@detail.summary.id}</p>
            <.copy_button id="copy-run-detail-id" target_id="run-detail-id" label="Copy run ID" />
          </div>
        </div>
        <div class="squid-sonar-detail-header-actions">
          <.status_badge status={@detail.summary.status} />
        </div>
      </header>

      <div class="squid-sonar-detail-grid">
        <.detail_item label="Queue" value={format_value(@detail.summary.queue)} />
        <.detail_item label="Current step" value={format_step(@detail.summary.current_step)} />
        <.detail_item label="Status" value={format_value(@detail.summary.status)} />
        <.detail_item
          label="Thread revisions"
          value={"run=#{@detail.summary.thread_revisions.run} dispatch=#{@detail.summary.thread_revisions.dispatch}"}
        />
      </div>

      <section class="squid-sonar-detail-panel squid-sonar-summary-json-panel">
        <.panel_heading
          title="Run summary JSON"
          description="Only values already visible in this run summary are included."
          level={:h3}
        >
          <:actions>
            <.copy_button
              id="copy-run-summary-json"
              target_id="run-summary-json"
              label="Copy safe JSON"
            />
          </:actions>
        </.panel_heading>
        <pre id="run-summary-json" class="squid-sonar-workflow-raw-json"><code>{run_summary_json(@detail.summary)}</code></pre>
      </section>

      <div class="squid-sonar-detail-columns">
        <section class="squid-sonar-detail-panel">
          <h3>Diagnosis</h3>
          <.detail_item label="Reason" value={explanation_reason(@detail.explanation)} />
          <.detail_item label="Suggested actions" value={next_actions(@detail.explanation)} />
          <.detail_item label="Last error" value={last_error(@detail.last_error)} variant={:code} />
        </section>

        <section class="squid-sonar-detail-panel">
          <h3>Journal evidence</h3>
          <.detail_item label="Planned runnables" value={length(@detail.planned_runnables)} />
          <.detail_item label="Attempts" value={length(@detail.attempts)} />
          <.detail_item label="Anomalies" value={length(@detail.anomalies)} />
        </section>
      </div>

      <%= if deadline = @detail.summary.deadline do %>
        <section class="squid-sonar-detail-panel squid-sonar-deadline-panel">
          <h3>Deadline</h3>
          <.detail_item label="State" value={format_deadline_status(deadline_status(deadline))} />
          <.detail_item label="Step" value={deadline_step(deadline)} />
          <.detail_item label="Due at" value={deadline_time(deadline, :due_at)} />
          <.detail_item label="Due soon at" value={deadline_time(deadline, :due_soon_at)} />
          <.detail_item label="Escalated at" value={deadline_time(deadline, :escalated_at)} />
          <.detail_item label="Escalation" value={deadline_escalation(deadline)} />
        </section>
      <% end %>

      <section
        :if={@detail.live_claims != []}
        class="squid-sonar-detail-panel squid-sonar-live-claim-panel"
      >
        <h3>Live claims</h3>
        <p>
          Claim and heartbeat recovery evidence; external side effects remain owned by the runtime or host backend.
        </p>
        <.detail_item label="Suggested actions" value={next_actions(@detail.explanation)} />
        <div class="squid-sonar-recovery-policy-list">
          <article
            :for={claim <- @detail.live_claims}
            class="squid-sonar-recovery-policy-row"
          >
            <strong>{format_step(claim.step)}</strong>
            <div class="squid-sonar-recovery-policy-tags">
              <span>{claim_status_label(claim.status)}</span>
              <span :if={claim.owner_id}>owner {claim.owner_id}</span>
              <span :if={claim.claim_id}>claim {claim.claim_id}</span>
              <span :if={claim.last_heartbeat_at}>
                last heartbeat {format_time(claim.last_heartbeat_at)}
              </span>
              <span :if={claim.lease_until}>lease until {format_time(claim.lease_until)}</span>
              <span :if={claim.runnable_key}>runnable {claim.runnable_key}</span>
              <span :if={claim.attempt_number}>attempt {claim.attempt_number}</span>
            </div>
            <div
              :if={claim.anomalies != []}
              class="squid-sonar-recovery-policy-tags"
            >
              <span :for={anomaly <- claim.anomalies}>
                evidence {format_claim_anomaly(anomaly)}
              </span>
            </div>
          </article>
        </div>
      </section>

      <section
        :if={@detail.compensation_evidence != []}
        class="squid-sonar-detail-panel squid-sonar-recovery-policy-panel"
      >
        <h3>Compensation evidence</h3>
        <p>
          Read-only rollback and undo evidence; SquidSonar does not execute compensation from this summary.
        </p>
        <div class="squid-sonar-recovery-policy-list">
          <div
            :for={evidence <- @detail.compensation_evidence}
            class="squid-sonar-recovery-policy-row"
          >
            <strong>{evidence.step}</strong>
            <div class="squid-sonar-recovery-policy-tags">
              <span>{compensation_status_label(evidence.status)}</span>
              <span :if={evidence.compensation_callback}>
                via {evidence.compensation_callback}
              </span>
              <span :if={evidence.policy_status}>
                policy {format_policy_value(evidence.policy_status)}
              </span>
              <span :if={evidence.compensation_step}>{evidence.compensation_step}</span>
              <span :if={evidence.failure_reason}>reason {evidence.failure_reason}</span>
              <span :if={evidence.irreversible? == true}>irreversible</span>
              <span :if={evidence.compensatable? == false}>non-compensatable</span>
              <span :if={evidence.replay}>replay {format_policy_value(evidence.replay)}</span>
              <span :if={evidence.recovery}>recovery {format_policy_value(evidence.recovery)}</span>
            </div>
          </div>
        </div>
      </section>

      <section
        :if={@detail.dynamic_work_overlays != []}
        class="squid-sonar-detail-panel squid-sonar-dynamic-work-panel"
      >
        <h3>Dynamic work overlays</h3>
        <p>
          Runtime-authored structure is inspection-only here; SquidSonar is not treating
          dynamic nodes as executable planner controls.
        </p>
        <div class="squid-sonar-recovery-policy-list">
          <article
            :for={overlay <- @detail.dynamic_work_overlays}
            class="squid-sonar-recovery-policy-row"
          >
            <strong>{format_dynamic_overlay_key(overlay)}</strong>
            <div class="squid-sonar-recovery-policy-tags">
              <span>origin {format_step(overlay.origin_node_id)}</span>
              <span :if={overlay.status}>status {format_policy_value(overlay.status)}</span>
              <span :if={overlay.reason}>reason {format_policy_value(overlay.reason)}</span>
              <span>{pluralize(overlay.node_count, "node")}</span>
              <span>{pluralize(overlay.edge_count, "edge")}</span>
              <span :if={overlay.recorded_at}>recorded {format_time(overlay.recorded_at)}</span>
            </div>
            <div class="squid-sonar-recovery-policy-tags">
              <span :if={overlay.added_node_ids != []}>
                nodes {Enum.join(overlay.added_node_ids, ", ")}
              </span>
              <span :if={overlay.added_edge_ids != []}>
                edges {Enum.join(overlay.added_edge_ids, ", ")}
              </span>
            </div>
          </article>
        </div>
      </section>

      <section
        :if={@detail.deferred_continuations != []}
        class="squid-sonar-detail-panel squid-sonar-deferred-continuation-panel"
      >
        <h3>Deferred continuations</h3>
        <p>
          Deferred wake-up metadata, target continuation, decision context, and safe cancellation and replay guidance.
        </p>
        <div class="squid-sonar-recovery-policy-list">
          <article
            :for={deferred <- @detail.deferred_continuations}
            class="squid-sonar-recovery-policy-row"
          >
            <strong>{format_step(deferred.step)}</strong>
            <div class="squid-sonar-recovery-policy-tags">
              <span :if={deferred.reason}>reason {format_policy_value(deferred.reason)}</span>
              <span :if={deferred.target_step}>target {format_step(deferred.target_step)}</span>
              <span :if={deferred.target_branch}>branch {deferred.target_branch}</span>
              <span :if={deferred.visible_at}>visible {format_time(deferred.visible_at)}</span>
              <span :if={deferred.next_visible_at}>
                next wakeup {format_time(deferred.next_visible_at)}
              </span>
              <span :if={deferred.deferred_at}>deferred {format_time(deferred.deferred_at)}</span>
              <span :if={deferred.runnable_key}>runnable {deferred.runnable_key}</span>
              <span :if={deferred.from_runnable_key}>from {deferred.from_runnable_key}</span>
              <span :if={not is_nil(deferred.wakeup_emitted?)}>
                wakeup emitted? {format_value(deferred.wakeup_emitted?)}
              </span>
            </div>
            <div
              :if={deferred.decision_context != %{}}
              class="squid-sonar-recovery-policy-tags"
            >
              <span>context {format_deferred_context(deferred.decision_context)}</span>
            </div>
          </article>
        </div>
      </section>

      <section class="squid-sonar-detail-panel">
        <div class="squid-sonar-workflow-panel-heading">
          <h3>Workflow</h3>
          <div :if={control_actions?(@detail)} class="squid-sonar-workflow-panel-actions">
            <.run_control_buttons detail={@detail} />
          </div>
        </div>

        <div
          class="squid-sonar-workflow-panel-tabs"
          role="tablist"
          aria-label="Workflow inspection view"
        >
          <button
            type="button"
            role="tab"
            phx-click="show_visual_workflow_panel"
            phx-value-view="visual"
            aria-selected={@workflow_panel_view == :visual}
            class={[
              "squid-sonar-workflow-panel-tab",
              @workflow_panel_view == :visual && "is-active"
            ]}
          >
            Visual graph
          </button>
          <button
            type="button"
            role="tab"
            phx-click="show_raw_workflow_panel"
            phx-value-view="raw"
            aria-selected={@workflow_panel_view == :raw}
            class={[
              "squid-sonar-workflow-panel-tab",
              @workflow_panel_view == :raw && "is-active"
            ]}
          >
            Raw inspection
          </button>
        </div>

        <%= if @workflow_panel_view == :raw do %>
          <div class="squid-sonar-workflow-raw">
            <div class="squid-sonar-workflow-graph-heading">
              <div class="squid-sonar-workflow-graph-heading-copy">
                <span class="squid-sonar-section-label">Public graph payload</span>
                <div class="squid-sonar-workflow-graph-heading-title">
                  <strong>Raw graph inspection</strong>
                  <.status_badge status={@detail.summary.status} />
                </div>
                <span>
                  {format_workflow(@detail.summary.workflow)} · {format_value(@detail.summary.queue)}
                </span>
              </div>
            </div>

            <div class="squid-sonar-workflow-raw-actions">
              <.copy_button
                id="copy-run-graph-json"
                target_id="run-graph-json"
                label="Copy safe JSON"
              />
            </div>
            <pre id="run-graph-json" class="squid-sonar-workflow-raw-json"><code>{raw_graph_inspection_json(@detail.graph_inspection)}</code></pre>
          </div>
        <% else %>
          <%= if @detail.workflow_graph.nodes == [] do %>
            <p class="squid-sonar-muted-line">No workflow graph loaded.</p>
          <% else %>
            <div class="squid-sonar-workflow-graph">
              <% layout = workflow_graph_layout(@detail.workflow_graph) %>

              <div class="squid-sonar-workflow-graph-heading">
                <div class="squid-sonar-workflow-graph-heading-copy">
                  <span class="squid-sonar-section-label">Journal-backed runtime</span>
                  <div class="squid-sonar-workflow-graph-heading-title">
                    <strong>{graph_mode_title(@detail.workflow_graph.mode)}</strong>
                    <.graph_mode_badge mode={@detail.workflow_graph.mode} />
                    <.status_badge status={@detail.summary.status} />
                  </div>
                  <span>
                    {format_workflow(@detail.summary.workflow)} · {format_value(@detail.summary.queue)}
                  </span>
                </div>
              </div>

              <div class="squid-sonar-workflow-graph-evidence">
                <div class="squid-sonar-workflow-graph-evidence-item">
                  <span>Current step</span>
                  <strong>{format_step(@detail.summary.current_step)}</strong>
                </div>
                <div class="squid-sonar-workflow-graph-evidence-item">
                  <span>Last reason</span>
                  <strong>{explanation_reason(@detail.explanation)}</strong>
                </div>
                <div class="squid-sonar-workflow-graph-evidence-item">
                  <span>Next actions</span>
                  <strong>{next_actions(@detail.explanation)}</strong>
                </div>
                <div class="squid-sonar-workflow-graph-evidence-item">
                  <span>Attempts</span>
                  <strong>{length(@detail.attempts)}</strong>
                </div>
              </div>

              <div
                class="squid-sonar-workflow-stage"
                style={workflow_stage_style(layout)}
              >
                <span
                  :for={segment <- layout.segments}
                  class={[
                    "squid-sonar-workflow-edge-segment",
                    "squid-sonar-workflow-edge-segment-#{segment.orientation}"
                  ]}
                  style={workflow_segment_style(segment)}
                />
                <span
                  :for={port <- layout.ports}
                  class="squid-sonar-workflow-port"
                  style={workflow_port_style(port)}
                />

                <article
                  :for={item <- layout.nodes}
                  class={[
                    "squid-sonar-workflow-node",
                    "squid-sonar-workflow-node-#{item.node.status}",
                    item.node.dynamic? && "squid-sonar-workflow-node-dynamic",
                    compensation_node?(item.node) && "squid-sonar-workflow-node-compensation",
                    item.node.current? && "squid-sonar-workflow-node-current",
                    item.node.terminal? && "squid-sonar-workflow-node-terminal"
                  ]}
                  style={workflow_node_style(item)}
                >
                  <div class="squid-sonar-workflow-node-main">
                    <span class={[
                      "squid-sonar-workflow-status-icon",
                      "squid-sonar-workflow-status-icon-#{item.node.status}"
                    ]} />
                    <strong>{item.node.label}</strong>
                    <span :if={item.node.dynamic?} class="squid-sonar-section-label">Dynamic</span>
                  </div>
                  <span class="squid-sonar-workflow-node-status">
                    {format_graph_status(item.node.status)}
                  </span>
                  <%= if recovery = compensation_recovery(item.node) do %>
                    <div
                      class="squid-sonar-workflow-node-recovery-panel"
                      title={"Rollback #{recovery.status} via #{recovery.callback}"}
                    >
                      <span class="squid-sonar-workflow-node-recovery-label">Rollback</span>
                      <div class="squid-sonar-workflow-node-recovery-meta">
                        <strong>{recovery.callback}</strong>
                        <em>{recovery.status}</em>
                      </div>
                    </div>
                  <% end %>
                  <%= if compensation = compensation_node(item.node) do %>
                    <div
                      class="squid-sonar-workflow-node-recovery-panel"
                      title={compensation_status_label(compensation.status)}
                    >
                      <span class="squid-sonar-workflow-node-recovery-label">Compensation</span>
                      <div class="squid-sonar-workflow-node-recovery-meta">
                        <strong>{compensation.origin}</strong>
                        <em>{compensation_status_label(compensation.status)}</em>
                      </div>
                    </div>
                  <% end %>
                  <%= if deadline = deadline_state(item.node) do %>
                    <div
                      class={[
                        "squid-sonar-workflow-node-deadline",
                        "squid-sonar-workflow-node-deadline-#{deadline_status(deadline)}"
                      ]}
                      title={"Deadline #{format_deadline_status(deadline_status(deadline))}"}
                    >
                      <span class="squid-sonar-workflow-node-deadline-label">Deadline</span>
                      <div class="squid-sonar-workflow-node-deadline-meta">
                        <strong>{format_deadline_status(deadline_status(deadline))}</strong>
                        <em>{deadline_time(deadline, :due_at)}</em>
                      </div>
                    </div>
                  <% end %>
                </article>
              </div>
            </div>
          <% end %>
        <% end %>
      </section>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :variant, :atom, default: :strong

  @spec detail_item(map()) :: Phoenix.LiveView.Rendered.t()
  def detail_item(assigns) do
    ~H"""
    <div class="squid-sonar-detail-item">
      <span>{@label}</span>
      <%= if @variant == :code do %>
        <code>{@value}</code>
      <% else %>
        <strong>{@value}</strong>
      <% end %>
    </div>
    """
  end

  attr :value, :any, required: true

  @spec timestamp(map()) :: Phoenix.LiveView.Rendered.t()
  def timestamp(assigns) do
    ~H"""
    <time>{@value |> format_time()}</time>
    """
  end

  defp human_status(status) do
    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_workflow(nil), do: "Unknown workflow"

  defp format_workflow(workflow) when is_atom(workflow) do
    workflow
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp format_workflow(workflow), do: to_string(workflow)

  defp format_step(nil), do: "None"
  defp format_step(step), do: format_value(step)

  defp format_value(nil), do: "None"
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: to_string(value)

  defp format_policy_value(nil), do: "unknown"

  defp format_policy_value(value) do
    value
    |> format_value()
    |> String.replace("_", " ")
  end

  defp compensation_status_label(:eligible), do: "compensation eligible"
  defp compensation_status_label(:succeeded), do: "compensation succeeded"
  defp compensation_status_label(:failed), do: "compensation failed"
  defp compensation_status_label(:skipped), do: "compensation skipped"
  defp compensation_status_label(:started), do: "compensation started"
  defp compensation_status_label(:retrying), do: "compensation retrying"
  defp compensation_status_label(:irreversible), do: "irreversible"
  defp compensation_status_label(:non_compensatable), do: "non-compensatable"
  defp compensation_status_label(status), do: format_policy_value(status)

  defp claim_status_label(:active), do: "active"
  defp claim_status_label(:expired), do: "expired"
  defp claim_status_label(:reclaimable), do: "reclaimable"
  defp claim_status_label(status), do: format_policy_value(status)

  defp format_claim_anomaly(anomaly) when is_map(anomaly) do
    case map_value(anomaly, :reason) do
      nil -> "claim anomaly"
      reason -> format_policy_value(reason)
    end
  end

  defp format_claim_anomaly(_anomaly), do: "claim anomaly"

  defp format_dynamic_overlay_key(%{dynamic_key: key}) when is_binary(key), do: key
  defp format_dynamic_overlay_key(%{origin_node_id: origin}) when is_binary(origin), do: origin
  defp format_dynamic_overlay_key(_overlay), do: "dynamic work"

  defp format_deferred_context(context) when is_map(context) do
    keys =
      context
      |> Enum.flat_map(fn
        {key, _value} when is_binary(key) or is_atom(key) -> [format_policy_value(key)]
        _other -> []
      end)
      |> Enum.sort()

    if keys == [], do: "present", else: Enum.join(keys, ", ")
  end

  defp format_deferred_context(_context), do: "present"

  defp pluralize(1, label), do: "1 #{label}"
  defp pluralize(count, label), do: "#{count} #{label}s"

  defp format_time(nil), do: "Unknown"

  defp format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp format_time(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
  end

  defp format_time(value), do: to_string(value)

  defp deadline_filter_options do
    [
      {:all, "All deadlines"},
      {:on_time, "On time"},
      {:due_soon, "Due soon"},
      {:overdue, "Overdue"},
      {:escalated, "Escalated"}
    ]
  end

  defp deadline_state(%{deadline: deadline}) when is_map(deadline), do: deadline
  defp deadline_state(_node), do: nil

  defp deadline_status(deadline) do
    case map_value(deadline, :status) do
      status when status in [:on_time, :due_soon, :overdue, :escalated] -> status
      "on_time" -> :on_time
      "due_soon" -> :due_soon
      "overdue" -> :overdue
      "escalated" -> :escalated
      _status -> :none
    end
  end

  defp deadline_step(deadline), do: format_step(map_value(deadline, :step))

  defp deadline_time(deadline, key) do
    case map_value(deadline, key) do
      nil -> "None"
      value -> format_time(value)
    end
  end

  defp deadline_escalation(deadline) do
    case map_value(deadline, :escalation) do
      escalation when is_map(escalation) ->
        escalation
        |> map_value(:outcome)
        |> format_value()

      escalation ->
        format_value(escalation)
    end
  end

  defp format_deadline_status(:none), do: "None"

  defp format_deadline_status(status) do
    status
    |> format_value()
    |> String.replace("_", " ")
  end

  defp run_path(prefix, run_id), do: "#{prefix}/runs/#{run_id}"

  defp explanation_reason(nil), do: "Unknown"
  defp explanation_reason(%{reason: reason}), do: format_value(reason)
  defp explanation_reason(_explanation), do: "Unknown"

  defp next_actions(nil), do: "None"

  defp next_actions(%{next_actions: actions}) do
    case List.wrap(actions) do
      [] -> "None"
      actions -> Enum.map_join(actions, ", ", &format_value/1)
    end
  end

  defp next_actions(_explanation), do: "None"

  defp last_error(nil), do: "None"

  defp last_error(error) when is_map(error) do
    case Map.take(error, [:code, "code"]) do
      empty when empty == %{} -> "Present"
      safe_error -> inspect(safe_error)
    end
  end

  defp last_error(_error), do: "Present"

  defp workflow_graph_layout(graph), do: WorkflowGraphLayout.build(graph)

  defp workflow_stage_style(%{width: width, height: height}) do
    "width: #{round(width)}px; height: #{round(height)}px;"
  end

  defp workflow_node_style(%{x: x, y: y, width: width, height: height}) do
    "left: #{round(x)}px; top: #{round(y)}px; width: #{round(width)}px; min-height: #{round(height)}px;"
  end

  defp workflow_segment_style(%{x: x, y: y, width: width, height: height}) do
    "left: #{round(x)}px; top: #{round(y)}px; width: #{round(width)}px; height: #{round(height)}px;"
  end

  defp workflow_port_style(%{x: x, y: y}) do
    "left: #{round(x)}px; top: #{round(y)}px;"
  end

  defp format_graph_status(:completed), do: "done"
  defp format_graph_status(:failed), do: "failed"
  defp format_graph_status(:retrying), do: "retrying"
  defp format_graph_status(:running), do: "running"
  defp format_graph_status(:paused), do: "paused"
  defp format_graph_status(:cancelled), do: "cancelled"
  defp format_graph_status(:waiting), do: "waiting"
  defp format_graph_status(:pending), do: "pending"
  defp format_graph_status(:deferred), do: "deferred"
  defp format_graph_status(status), do: format_value(status)

  defp compensation_recovery(%{recovery: recovery}) when is_map(recovery) do
    with compensation when is_map(compensation) <- map_value(recovery, :compensation),
         callback when (is_binary(callback) or is_atom(callback)) and not is_nil(callback) <-
           map_value(compensation, :callback) do
      %{
        callback: format_recovery_callback(callback),
        status:
          compensation
          |> Map.get(:status, Map.get(compensation, "status", :available))
          |> format_value()
      }
    else
      _other -> nil
    end
  end

  defp compensation_recovery(_node), do: nil

  defp compensation_node(%{name: name, status: status}) do
    case format_value(name) do
      "compensate:" <> origin ->
        %{origin: origin, status: compensation_graph_status(status)}

      _other ->
        nil
    end
  end

  defp compensation_node(_node), do: nil

  defp compensation_node?(node), do: not is_nil(compensation_node(node))

  defp compensation_graph_status(:completed), do: :succeeded
  defp compensation_graph_status(:failed), do: :failed
  defp compensation_graph_status(:skipped), do: :skipped
  defp compensation_graph_status(status) when status in [:running, :claimed], do: :started
  defp compensation_graph_status(status), do: status

  defp format_recovery_callback(callback) do
    callback
    |> format_value()
    |> String.replace_prefix("Elixir.", "")
  end

  defp raw_graph_inspection_json(graph_inspection) do
    graph_inspection
    |> normalize_graph_inspection()
    |> Jason.encode!(pretty: true)
  end

  defp run_summary_json(summary) do
    summary = %{
      "current_step" => summary.current_step,
      "id" => summary.id,
      "queue" => summary.queue,
      "status" => summary.status,
      "terminal" => summary.terminal?,
      "terminal_status" => summary.terminal_status,
      "thread_revisions" => summary.thread_revisions,
      "workflow" => format_workflow(summary.workflow)
    }

    Jason.encode!(summary, pretty: true)
  end

  defp normalize_graph_inspection(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> normalize_graph_inspection()
  end

  defp normalize_graph_inspection(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {to_string(key), normalize_graph_inspection(nested_value)}
    end)
  end

  defp normalize_graph_inspection(value) when is_list(value) do
    Enum.map(value, &normalize_graph_inspection/1)
  end

  defp normalize_graph_inspection(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> normalize_graph_inspection()
  end

  defp normalize_graph_inspection(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_graph_inspection(value), do: value

  defp graph_mode_label(:transition), do: "Transition"
  defp graph_mode_label(:dependency), do: "Dependency"
  defp graph_mode_label(:history), do: "History"

  defp graph_mode_title(:transition), do: "Transition graph"
  defp graph_mode_title(:dependency), do: "Dependency graph"
  defp graph_mode_title(:history), do: "History graph"

  defp flash_message(flash, key) do
    Phoenix.Flash.get(flash, key) || Map.get(flash, Atom.to_string(key))
  end

  defp control_actions?(detail), do: available_control_actions(detail) != []

  attr :detail, :map, required: true

  @spec run_control_buttons(map()) :: Phoenix.LiveView.Rendered.t()
  def run_control_buttons(assigns) do
    available_actions = available_control_actions(assigns.detail)

    assigns = assign(assigns, :available_actions, available_actions)

    ~H"""
    <div class="squid-sonar-control-buttons">
      <%= if :cancel in @available_actions do %>
        <button
          class="squid-sonar-control-button squid-sonar-control-button-danger"
          type="button"
          phx-click="cancel"
          phx-value-run-id={@detail.summary.id}
          data-confirm="Are you sure you want to cancel this run?"
        >
          Cancel
        </button>
      <% end %>

      <%= if :resume in @available_actions do %>
        <button
          class="squid-sonar-control-button squid-sonar-control-button-primary"
          type="button"
          phx-click="resume"
          phx-value-run-id={@detail.summary.id}
        >
          Resume
        </button>
      <% end %>

      <%= if :approve in @available_actions do %>
        <button
          class="squid-sonar-control-button squid-sonar-control-button-success"
          type="button"
          phx-click="approve"
          phx-value-run-id={@detail.summary.id}
        >
          Approve
        </button>
      <% end %>

      <%= if :reject in @available_actions do %>
        <button
          class="squid-sonar-control-button squid-sonar-control-button-danger"
          type="button"
          phx-click="reject"
          phx-value-run-id={@detail.summary.id}
        >
          Reject
        </button>
      <% end %>

      <%= if :replay in @available_actions do %>
        <button
          class="squid-sonar-control-button squid-sonar-control-button-secondary"
          type="button"
          phx-click="replay"
          phx-value-run-id={@detail.summary.id}
          data-confirm="Are you sure you want to replay this run?"
        >
          Replay
        </button>
      <% end %>
    </div>
    """
  end

  defp available_control_actions(%{controls_allowed?: false}), do: []

  defp available_control_actions(%{summary: summary, explanation: explanation}) do
    status = summary.status
    terminal? = summary.terminal?
    next_actions = Map.get(explanation, :next_actions, [])
    manual_resolution? = :resolve_manual_step in next_actions
    approval_step? = approval_step?(explanation)
    pause_step? = pause_step?(explanation, status)

    actions =
      []
      |> maybe_add_control_action(not terminal? and status not in [:cancelled], [:cancel])
      |> maybe_add_control_action(manual_resolution? and pause_step?, [:resume])
      |> maybe_add_control_action(manual_resolution? and approval_step?, [:approve, :reject])
      |> maybe_add_control_action(terminal?, [:replay])

    Enum.reverse(actions)
  end

  defp maybe_add_control_action(actions, true, new_actions), do: new_actions ++ actions
  defp maybe_add_control_action(actions, false, _new_actions), do: actions

  defp pause_step?(explanation, status) do
    case manual_kind(explanation) do
      "pause" -> true
      nil -> status == :paused and not approval_step?(explanation)
      _kind -> false
    end
  end

  defp approval_step?(explanation) do
    case manual_kind(explanation) do
      "approval" -> true
      nil -> approval_step_name?(explanation)
      _kind -> false
    end
  end

  defp manual_kind(%{details: details, evidence: evidence}) do
    case manual_kind_from_map(details) do
      nil ->
        evidence
        |> manual_state_from_evidence()
        |> manual_kind_from_map()

      kind ->
        kind
    end
  end

  defp manual_kind(_explanation), do: nil

  defp manual_kind_from_map(map) when is_map(map) do
    map
    |> map_value(:kind)
    |> normalize_manual_kind()
  end

  defp manual_kind_from_map(_map), do: nil

  defp manual_state_from_evidence(evidence) when is_map(evidence) do
    map_value(evidence, :manual_state)
  end

  defp manual_state_from_evidence(_evidence), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_value, _key), do: nil

  defp normalize_manual_kind(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp normalize_manual_kind(kind) when is_binary(kind), do: kind
  defp normalize_manual_kind(_kind), do: nil

  defp approval_step_name?(%{step: step}) when is_binary(step) do
    step = String.downcase(step)
    String.contains?(step, "approval") or String.contains?(step, "review")
  end

  defp approval_step_name?(_explanation), do: false
end
