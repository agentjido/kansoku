defmodule KansokuWeb.RunLiveTest do
  use ExUnit.Case, async: false

  import Kansoku.ReadModelFixtures

  defmodule CheckoutWorkflow do
    use Jizoku.Workflow

    workflow do
      trigger :manual do
        manual()
      end

      step(:load_order, :log, message: "load order")
      step(:capture_payment, :log, message: "capture payment")
      step(:send_receipt, :log, message: "send receipt")

      transition(:load_order, on: :ok, to: :capture_payment)
      transition(:capture_payment, on: :ok, to: :send_receipt)
      transition(:send_receipt, on: :ok, to: :complete)
    end
  end

  defmodule MissingWorkflow do
  end

  import Phoenix.LiveViewTest

  alias Jizoku.ReadModel.Timeline
  alias Jizoku.ReadModel.Timeline.Event
  alias Kansoku.FakeJizokuClient
  alias KansokuWeb.RunLive
  alias Phoenix.LiveView.Socket

  setup do
    previous_client = Application.get_env(:kansoku, :jizoku_client)
    Application.put_env(:kansoku, :jizoku_client, FakeJizokuClient)

    on_exit(fn ->
      if previous_client do
        Application.put_env(:kansoku, :jizoku_client, previous_client)
      else
        Application.delete_env(:kansoku, :jizoku_client)
      end
    end)
  end

  test "renders run detail through the run context" do
    deadline = %{
      status: :overdue,
      step: "capture_payment",
      due_at: ~U[2026-05-15 10:15:00Z],
      due_soon_at: ~U[2026-05-15 10:10:00Z],
      escalation: %{outcome: :operator_action}
    }

    snapshot =
      snapshot(:running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :attempt_visible,
        deadline: deadline,
        attempts: [attempt("capture_payment", :claimed, 1, %{"message" => "Gateway unavailable"})],
        planned_runnables: [%{runnable_key: "capture_payment"}],
        anomalies: [%{kind: :stale_projection}]
      )

    graph =
      graph_inspection(:running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("load_order", :completed, false),
          graph_node("capture_payment", :running, true, deadline: deadline),
          graph_node("send_receipt", :waiting, false)
        ],
        edges: [
          graph_edge("load_order", "capture_payment", :ok),
          graph_edge("capture_payment", "send_receipt", :ok)
        ]
      )

    explanation =
      diagnostic(
        :running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment",
        summary: "A dispatch attempt is visible and waiting for a worker claim.",
        details: %{
          visible_attempt_count: 1,
          deadline_status: :overdue,
          deadline_escalation: %{outcome: :operator_action}
        },
        next_actions: [:wait_for_worker_claim, :apply_host_escalation_policy],
        evidence: %{attempt_counts: %{claimed: 1}, deadline: deadline}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-1"}, "/kansoku/runs/run-1", mounted_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Kansoku"
    assert html =~ "Run detail"
    assert html =~ "Run summary"
    assert html =~ "Journal-backed runtime"
    assert html =~ "CheckoutWorkflow"
    assert html =~ "capture_payment"
    assert html =~ "Queue"
    assert html =~ "Status"
    assert html =~ "Thread revisions"
    assert html =~ "Transition graph"
    assert html =~ "Journal evidence"
    assert html =~ "Planned runnables"
    assert html =~ "Attempts"
    assert html =~ "Anomalies"
    assert html =~ "Deadline"
    assert html =~ "overdue"
    assert html =~ "operator_action"
    assert html =~ "2026-05-15T10:15:00Z"
    assert html =~ "Last error"
    assert html =~ "Present"
    refute html =~ "Gateway unavailable"
    assert html =~ "wait_for_worker_claim"
    assert html =~ "apply_host_escalation_policy"
    assert html =~ "kansoku-workflow-graph"
    assert html =~ "kansoku-workflow-node-deadline"
    refute html =~ "kansoku-workflow-panel-actions"
  end

  test "selects run detail tabs from stable URL params and defaults invalid tabs" do
    put_basic_run("run-tabs")

    FakeJizokuClient.put_inspect_run_timeline({:ok, timeline("run-tabs", [])})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, timeline_socket} =
      RunLive.handle_params(
        %{"id" => "run-tabs", "tab" => "timeline"},
        "/runs/run-tabs?tab=timeline",
        mounted_socket
      )

    assert timeline_socket.assigns.active_tab == :timeline

    timeline_html = rendered_to_string(RunLive.render(timeline_socket.assigns))

    assert timeline_html =~ ~s(id="run-tab-timeline")
    assert timeline_html =~ ~s(href="/runs/run-tabs?tab=timeline")
    assert timeline_html =~ ~s(id="run-tab-panel-timeline")
    assert timeline_html =~ ~s(aria-label="Run detail views")
    assert timeline_html =~ ~s(aria-current="page")
    refute timeline_html =~ ~s(role="tablist")
    refute timeline_html =~ ~s(role="tab")
    assert timeline_html =~ "CheckoutWorkflow"
    assert timeline_html =~ "running"

    {:noreply, default_socket} =
      RunLive.handle_params(
        %{"id" => "run-tabs", "tab" => "not-a-tab"},
        "/runs/run-tabs?tab=not-a-tab",
        mounted_socket
      )

    assert default_socket.assigns.active_tab == :overview
  end

  test "does not refetch run data for a same-run tab patch" do
    run_id = "run-tab-patch"
    workflow = Atom.to_string(CheckoutWorkflow)

    put_basic_run(run_id)

    FakeJizokuClient.put_inspect_run(fn ^run_id, _opts ->
      Process.put(:tab_patch_inspections, Process.get(:tab_patch_inspections, 0) + 1)

      {:ok,
       snapshot(:running,
         run_id: run_id,
         workflow: workflow,
         current_step: "capture_payment",
         reason: :attempt_visible
       )}
    end)

    FakeJizokuClient.put_inspect_run_timeline({:ok, timeline(run_id, [])})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, overview_socket} =
      RunLive.handle_params(%{"id" => run_id}, "/runs/#{run_id}", mounted_socket)

    {:noreply, timeline_socket} =
      RunLive.handle_params(
        %{"id" => run_id, "tab" => "timeline"},
        "/runs/#{run_id}?tab=timeline",
        overview_socket
      )

    assert Process.get(:tab_patch_inspections) == 1
    assert timeline_socket.assigns.active_tab == :timeline
    assert timeline_socket.assigns.detail.summary.id == run_id
  end

  test "renders timeline events chronologically and excludes redaction-sensitive details" do
    put_basic_run("run-timeline")

    later =
      %Event{
        type: :attempt_claimed,
        occurred_at: ~U[2026-05-15 10:10:00Z],
        run_id: "run-timeline",
        step_id: "capture_payment",
        status: :claimed,
        summary: "capture_payment attempt claimed",
        details: %{attempt_number: 2, claim_token: "timeline-secret"}
      }

    earlier =
      %Event{
        type: :run_started,
        occurred_at: ~U[2026-05-15 10:00:00Z],
        run_id: "run-timeline",
        status: :running,
        summary: "run started",
        details: %{payload: "payload-secret"}
      }

    FakeJizokuClient.put_inspect_run_timeline({:ok, timeline("run-timeline", [later, earlier])})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-timeline", "tab" => "timeline"},
        "/runs/run-timeline?tab=timeline",
        mounted_socket
      )

    html = rendered_to_string(RunLive.render(loaded_socket.assigns))
    {started_at, _length} = :binary.match(html, "run started")
    {claimed_at, _length} = :binary.match(html, "capture_payment attempt claimed")

    assert started_at < claimed_at
    assert html =~ ~s(data-timeline-type="run_started")
    assert html =~ ~s(data-timeline-type="attempt_claimed")
    assert html =~ "attempt 2"
    refute html =~ "timeline-secret"
    refute html =~ "payload-secret"
  end

  test "renders useful empty and partial timeline states" do
    put_basic_run("run-empty-timeline")

    FakeJizokuClient.put_inspect_run_timeline({:ok, timeline("run-empty-timeline", [])})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, empty_socket} =
      RunLive.handle_params(
        %{"id" => "run-empty-timeline", "tab" => "timeline"},
        "/runs/run-empty-timeline?tab=timeline",
        mounted_socket
      )

    empty_html = rendered_to_string(RunLive.render(empty_socket.assigns))
    assert empty_html =~ "No timestamped events available"
    refute empty_html =~ "Timeline data is partial"

    FakeJizokuClient.put_inspect_run_timeline({:error, :temporarily_unavailable})

    {:noreply, partial_socket} =
      RunLive.handle_params(
        %{"id" => "run-empty-timeline", "tab" => "timeline"},
        "/runs/run-empty-timeline?tab=timeline",
        mounted_socket
      )

    partial_html = rendered_to_string(RunLive.render(partial_socket.assigns))
    assert partial_html =~ "Timeline data is partial"
    assert partial_socket.assigns.detail.timeline_partial?
  end

  test "retains a terminal partial timeline while bounded retries fail" do
    run_id = "run-terminal-partial"
    workflow = Atom.to_string(CheckoutWorkflow)

    terminal_snapshot =
      snapshot(:completed,
        run_id: run_id,
        workflow: workflow,
        reason: :terminal
      )

    FakeJizokuClient.put_inspect_run(fn ^run_id, _opts ->
      case Process.get(:terminal_partial_inspections, 0) do
        0 ->
          Process.put(:terminal_partial_inspections, 1)
          {:ok, terminal_snapshot}

        _retry ->
          {:error, :temporarily_unavailable}
      end
    end)

    FakeJizokuClient.put_inspect_run_graph(
      {:ok, graph_inspection(:completed, run_id: run_id, workflow: workflow)}
    )

    FakeJizokuClient.put_explain_run(
      {:ok, diagnostic(:completed, run_id: run_id, workflow: workflow, reason: :terminal)}
    )

    FakeJizokuClient.put_inspect_run_timeline({:error, :temporarily_unavailable})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, partial_socket} =
      RunLive.handle_params(
        %{"id" => run_id, "tab" => "timeline"},
        "/runs/#{run_id}?tab=timeline",
        mounted_socket
      )

    assert partial_socket.assigns.detail.summary.id == run_id
    assert partial_socket.assigns.detail.timeline_partial?
    assert partial_socket.assigns.partial_timeline_refresh_attempts == 1

    {:noreply, first_retry_socket} = RunLive.handle_info(:refresh_run, partial_socket)
    {:noreply, final_retry_socket} = RunLive.handle_info(:refresh_run, first_retry_socket)

    assert final_retry_socket.assigns.detail.summary.id == run_id
    assert final_retry_socket.assigns.load_error == nil
    assert final_retry_socket.assigns.partial_timeline_refresh_attempts == 3
  end

  test "renders live claim and heartbeat recovery evidence" do
    active_lease_until = ~U[2026-05-15 10:45:00Z]
    active_heartbeat_at = ~U[2026-05-15 10:40:00Z]
    expired_lease_until = ~U[2026-05-15 10:05:00Z]

    active_claim =
      Map.merge(attempt("capture_payment", :claimed, 1, nil), %{
        runnable_key: "run-live-claims:capture_payment:1",
        owner_id: "worker-a",
        claim_id: "claim-active",
        last_heartbeat_at: active_heartbeat_at,
        lease_until: active_lease_until
      })

    expired_claim =
      Map.merge(attempt("reserve_inventory", :claimed, 1, nil), %{
        runnable_key: "run-live-claims:reserve_inventory:1",
        owner_id: "worker-b",
        claim_id: "claim-expired",
        lease_until: expired_lease_until
      })

    snapshot =
      snapshot(:running,
        run_id: "run-live-claims",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "reserve_inventory",
        reason: :expired_claim,
        attempts: [active_claim],
        expired_claims: [expired_claim],
        anomalies: [
          %{
            reason: :stale_claim,
            runnable_key: "run-live-claims:reserve_inventory:1",
            claim_id: "claim-expired",
            claim_token_hash: "secret-hash"
          }
        ]
      )

    graph =
      graph_inspection(:running,
        run_id: "run-live-claims",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "reserve_inventory",
        nodes: [
          graph_node("capture_payment", :running, false),
          graph_node("reserve_inventory", :running, true)
        ],
        edges: [
          graph_edge("capture_payment", "reserve_inventory", :ok)
        ]
      )

    explanation =
      diagnostic(:running,
        run_id: "run-live-claims",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :expired_claim,
        step: "reserve_inventory",
        summary: "A claimed dispatch attempt has expired and is recoverable.",
        details: %{
          expired_claim_count: 1,
          oldest_lease_until: expired_lease_until
        },
        next_actions: [:recover_expired_claim, :cancel]
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-live-claims"},
        "/kansoku/runs/run-live-claims",
        mounted_socket
      )

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Live claims"
    assert html =~ "Claim and heartbeat recovery evidence"
    assert html =~ "capture_payment"
    assert html =~ "active"
    assert html =~ "worker-a"
    assert html =~ "claim-active"
    assert html =~ "last heartbeat 2026-05-15T10:40:00Z"
    assert html =~ "lease until 2026-05-15T10:45:00Z"
    assert html =~ "reserve_inventory"
    assert html =~ "reclaimable"
    assert html =~ "worker-b"
    assert html =~ "claim-expired"
    assert html =~ "lease until 2026-05-15T10:05:00Z"
    assert html =~ "stale claim"
    assert html =~ "recover_expired_claim"
    assert html =~ "cancel"
    refute html =~ "secret-hash"
  end

  test "renders feedback after run control events" do
    snapshot =
      snapshot(:running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :attempt_visible
      )

    graph =
      graph_inspection(:running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("capture_payment", :running, true)
        ]
      )

    explanation =
      diagnostic(
        :running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment",
        next_actions: [:wait_for_worker_claim]
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    FakeJizokuClient.put_cancel(
      {:ok, snapshot(:cancelled, run_id: "run-1", workflow: Atom.to_string(CheckoutWorkflow))}
    )

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-1"},
        "/kansoku/runs/run-1",
        operator_socket(mounted_socket)
      )

    {:noreply, cancelled_socket} =
      RunLive.handle_event("cancel", %{"run-id" => "run-1"}, loaded_socket)

    feedback_html =
      cancelled_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert feedback_html =~ "Run cancelled successfully"
    assert feedback_html =~ "phx-hook=\"KansokuFlash\""
    assert feedback_html =~ "aria-label=\"Dismiss notification\""

    {:noreply, cleared_socket} = RunLive.handle_event("clear_flash", %{}, cancelled_socket)

    cleared_html =
      cleared_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    refute cleared_html =~ "Run cancelled successfully"
  end

  test "refreshes run detail after control feedback while the run is still active" do
    initial_snapshot =
      snapshot(:paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "wait_for_review",
        reason: :manual_intervention_required,
        manual_state: %{step: "wait_for_review", kind: "approval"}
      )

    running_snapshot =
      snapshot(:running,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "record_approval",
        reason: :attempt_visible,
        planned_runnables: [%{runnable_key: "record_approval"}]
      )

    completed_snapshot =
      snapshot(:completed,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "record_approval",
        reason: :terminal
      )

    FakeJizokuClient.put_inspect_run(fn
      "run-approval", _opts ->
        count = Process.get(:refresh_run_inspections, 0)
        Process.put(:refresh_run_inspections, count + 1)

        case count do
          0 -> {:ok, initial_snapshot}
          1 -> {:ok, running_snapshot}
          _count -> {:ok, completed_snapshot}
        end
    end)

    FakeJizokuClient.put_inspect_run_graph(fn run_id, _opts ->
      {:ok,
       graph_inspection(:running,
         run_id: run_id,
         workflow: Atom.to_string(CheckoutWorkflow),
         current_node_id: "record_approval",
         nodes: [graph_node("record_approval", :running, true)]
       )}
    end)

    FakeJizokuClient.put_explain_run(fn run_id, _opts ->
      {:ok,
       diagnostic(:running,
         run_id: run_id,
         workflow: Atom.to_string(CheckoutWorkflow),
         reason: :attempt_visible,
         step: "record_approval",
         next_actions: [:wait_for_worker_claim]
       )}
    end)

    FakeJizokuClient.put_approve({:ok, running_snapshot})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-approval"},
        "/kansoku/runs/run-approval",
        operator_socket(mounted_socket)
      )

    {:noreply, approved_socket} =
      RunLive.handle_event("approve", %{"run-id" => "run-approval"}, loaded_socket)

    assert approved_socket.assigns.detail.summary.status == :running

    {:noreply, refreshed_socket} = RunLive.handle_info(:refresh_run, approved_socket)

    assert refreshed_socket.assigns.detail.summary.status == :completed

    html =
      refreshed_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Run approved successfully"
    assert html =~ "record_approval"
  end

  test "renders approval controls without resume for approval pauses" do
    manual_state = %{step: "wait_for_review", kind: "approval"}

    snapshot =
      snapshot(:paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "wait_for_review",
        reason: :manual_intervention_required,
        manual_state: manual_state
      )

    graph =
      graph_inspection(:paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "wait_for_review",
        nodes: [
          graph_node("wait_for_review", :paused, true, manual_state: manual_state)
        ]
      )

    explanation =
      diagnostic(
        :paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :manual_intervention_required,
        step: "wait_for_review",
        details: manual_state,
        next_actions: [:resolve_manual_step],
        evidence: %{manual_state: manual_state}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-approval"},
        "/kansoku/runs/run-approval",
        operator_socket(mounted_socket)
      )

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Approve"
    assert html =~ "Reject"
    refute html =~ "Resume"
  end

  test "passes the configured control actor to approval decisions" do
    actor = %{"id" => "user-123", "type" => "operator", "name" => "Ada"}
    parent = self()

    snapshot =
      snapshot(:paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "wait_for_review",
        reason: :manual_intervention_required,
        manual_state: %{step: "wait_for_review", kind: "approval"}
      )

    graph =
      graph_inspection(:paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "wait_for_review",
        nodes: [
          graph_node("wait_for_review", :paused, true)
        ]
      )

    explanation =
      diagnostic(
        :paused,
        run_id: "run-approval",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :manual_intervention_required,
        step: "wait_for_review",
        details: %{step: "wait_for_review", kind: "approval"},
        next_actions: [:resolve_manual_step]
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    FakeJizokuClient.put_approve(fn run_id, attrs, _opts ->
      send(parent, {:approve_attrs, run_id, attrs})
      {:ok, snapshot(:running, run_id: run_id, workflow: Atom.to_string(CheckoutWorkflow))}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    actor_socket =
      mounted_socket
      |> operator_socket()
      |> Phoenix.Component.assign(:control_actor, actor)

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-approval"}, "/kansoku/runs/run-approval", actor_socket)

    {:noreply, _approved_socket} =
      RunLive.handle_event("approve", %{"run-id" => "run-approval"}, loaded_socket)

    assert_receive {:approve_attrs, "run-approval", %{actor: ^actor}}
  end

  test "renders control errors without leaking internal reason details" do
    snapshot =
      snapshot(:running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :attempt_visible
      )

    graph =
      graph_inspection(:running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("capture_payment", :running, true)
        ]
      )

    explanation =
      diagnostic(
        :running,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment",
        next_actions: [:wait_for_worker_claim]
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})
    FakeJizokuClient.put_cancel({:error, {:missing_config, [:repo]}})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-1"},
        "/kansoku/runs/run-1",
        operator_socket(mounted_socket)
      )

    {:noreply, cancelled_socket} =
      RunLive.handle_event("cancel", %{"run-id" => "run-1"}, loaded_socket)

    html =
      cancelled_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Failed to cancel run."
    refute html =~ "missing_config"
  end

  test "renders the new run after replay succeeds" do
    source_snapshot =
      snapshot(:completed,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "send_receipt",
        reason: :terminal
      )

    replayed_snapshot =
      snapshot(:running,
        run_id: "run-2",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "load_order",
        reason: :attempt_visible
      )

    graph =
      graph_inspection(:completed,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "send_receipt",
        nodes: [
          graph_node("send_receipt", :completed, true)
        ]
      )

    explanation =
      diagnostic(
        :completed,
        run_id: "run-1",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :terminal,
        step: "send_receipt",
        next_actions: [:inspect_terminal_run]
      )

    FakeJizokuClient.put_inspect_run(fn
      "run-1", _opts -> {:ok, source_snapshot}
      "run-2", _opts -> {:ok, replayed_snapshot}
    end)

    FakeJizokuClient.put_inspect_run_graph(fn
      "run-1", _opts ->
        {:ok, graph}

      "run-2", _opts ->
        {:ok,
         graph_inspection(:running,
           run_id: "run-2",
           workflow: Atom.to_string(CheckoutWorkflow),
           current_node_id: "load_order",
           nodes: [
             graph_node("load_order", :running, true)
           ]
         )}
    end)

    FakeJizokuClient.put_explain_run(fn
      "run-1", _opts ->
        {:ok, explanation}

      "run-2", _opts ->
        {:ok,
         diagnostic(:running,
           run_id: "run-2",
           workflow: Atom.to_string(CheckoutWorkflow),
           reason: :attempt_visible,
           step: "load_order",
           next_actions: [:wait_for_worker_claim]
         )}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-1"},
        "/kansoku/runs/run-1",
        operator_socket(mounted_socket)
      )

    FakeJizokuClient.put_replay({:ok, replayed_snapshot})

    {:noreply, replayed_socket} =
      RunLive.handle_event("replay", %{"run-id" => "run-1"}, loaded_socket)

    assert replayed_socket.assigns.detail.summary.id == "run-2"
    assert {:live, :patch, %{to: "/runs/run-2"}} = replayed_socket.redirected
  end

  test "renders journal history graphs when the workflow definition is unavailable" do
    snapshot =
      snapshot(:completed,
        run_id: "run-history",
        workflow: Atom.to_string(MissingWorkflow),
        current_step: "capture_payment",
        reason: :terminal,
        attempts: [
          attempt("load_order", :completed, 1, nil),
          attempt("capture_payment", :completed, 1, nil)
        ]
      )

    graph =
      graph_inspection(:completed,
        run_id: "run-history",
        workflow: Atom.to_string(MissingWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("load_order", :completed, false),
          graph_node("capture_payment", :completed, true)
        ],
        edges: [
          graph_edge("load_order", "capture_payment", :next)
        ]
      )

    explanation =
      diagnostic(
        :completed,
        run_id: "run-history",
        workflow: Atom.to_string(MissingWorkflow),
        reason: :terminal,
        step: "capture_payment",
        summary: "The run is terminal according to the run journal.",
        details: %{terminal?: true, terminal_status: :completed},
        next_actions: [:inspect_terminal_run],
        evidence: %{terminal_status: :completed}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-history"}, "/kansoku/runs/run-history", mounted_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Journal-backed runtime"
    assert html =~ "History graph"
    assert html =~ "Journal evidence"
    assert html =~ "load_order"
    assert html =~ "capture_payment"
  end

  test "switches the workflow panel to raw graph inspection" do
    recovery = compensation_recovery("ReleaseInventory")

    graph =
      graph_inspection(:running,
        run_id: "run-raw-graph",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        anomalies: [%{kind: :missing_recovery_metadata}],
        nodes: [
          graph_node("capture_payment", :running, true,
            recovery:
              compensation_recovery("ReleaseInventory",
                failure: %{strategy: :compensation, target: "release_inventory"}
              )
          )
        ],
        edges: [
          graph_edge("capture_payment", "release_inventory", :error, recovery: :compensation)
        ]
      )

    snapshot =
      snapshot(:running,
        run_id: "run-raw-graph",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :attempt_visible
      )

    explanation =
      diagnostic(
        :running,
        run_id: "run-raw-graph",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment",
        next_actions: [:wait_for_worker_claim],
        evidence: recovery_policy_evidence("capture_payment", recovery)
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-raw-graph"},
        "/kansoku/runs/run-raw-graph",
        mounted_socket
      )

    assert loaded_socket.assigns.detail.explanation.evidence ==
             recovery_policy_evidence("capture_payment", recovery)

    visual_html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert visual_html =~ "Transition graph"
    assert visual_html =~ "Raw data"
    assert visual_html =~ "Rollback"
    assert visual_html =~ "kansoku-workflow-node-recovery-panel"
    assert visual_html =~ "ReleaseInventory"
    assert visual_html =~ "available"
    refute visual_html =~ ~s("current_node_ids")

    {:noreply, raw_socket} =
      RunLive.handle_event("select_workflow_panel", %{"view" => "raw"}, loaded_socket)

    raw_html =
      raw_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert raw_html =~ "Raw graph inspection"
    assert raw_html =~ "&quot;current_node_ids&quot;"
    assert raw_html =~ "&quot;nodes&quot;"
    assert raw_html =~ "&quot;edges&quot;"
    assert raw_html =~ "&quot;recovery&quot;"
    assert raw_html =~ "&quot;anomalies&quot;"
    assert raw_html =~ "missing_recovery_metadata"
    assert raw_html =~ "ReleaseInventory"
  end

  test "renders dynamic work overlays in visual and raw inspection views" do
    origin = %{step: "capture_payment", branch: "fraud_review"}
    recorded_at = ~U[2026-05-15 10:17:00Z]

    dynamic_work = [
      %{
        "dynamic_key" => "fraud_review",
        "status" => "recorded",
        "reason" => "risk_signal",
        "origin" => origin,
        "nodes" => [
          %{"id" => "fraud_review", "action" => "review_risk", "metadata" => %{"queue" => "risk"}}
        ],
        "edges" => [
          %{
            "id" => "capture_payment:dynamic:fraud_review",
            "from" => "capture_payment",
            "to" => "fraud_review"
          }
        ],
        "recorded_at" => recorded_at
      },
      %{"nodes" => "stale"}
    ]

    base_graph =
      graph_inspection(:running,
        run_id: "run-dynamic-work",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("capture_payment", :running, true),
          %{
            graph_node("fraud_review", :pending, false)
            | dynamic?: true,
              origin: origin,
              metadata: %{queue: "risk"}
          }
        ],
        edges: [
          %{graph_edge("capture_payment", "fraud_review", :dynamic) | type: :dynamic}
        ]
      )

    graph = %{
      base_graph
      | dynamic_work: dynamic_work,
        dynamic_work_overlays: [
          %{
            "dynamic_key" => "fraud_review",
            "status" => "recorded",
            "reason" => "risk_signal",
            "origin" => origin,
            "origin_node_id" => "capture_payment",
            "added_node_ids" => ["fraud_review"],
            "added_edge_ids" => ["capture_payment:dynamic:fraud_review"],
            "node_count" => 1,
            "edge_count" => 1,
            "recorded_at" => recorded_at
          },
          %{}
        ]
    }

    snapshot =
      snapshot(:running,
        run_id: "run-dynamic-work",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :attempt_visible
      )

    explanation =
      diagnostic(:running,
        run_id: "run-dynamic-work",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment",
        next_actions: [:wait_for_worker_claim]
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-dynamic-work"},
        "/kansoku/runs/run-dynamic-work",
        mounted_socket
      )

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Dynamic work overlays"
    assert html =~ "inspection-only"
    assert html =~ "fraud_review"
    assert html =~ "capture_payment"
    assert html =~ "risk signal"
    assert html =~ "1 node"
    assert html =~ "1 edge"
    assert html =~ "2026-05-15T10:17:00Z"
    assert html =~ "kansoku-workflow-node-dynamic"
    assert html =~ "Dynamic"

    {:noreply, raw_socket} =
      RunLive.handle_event("select_workflow_panel", %{"view" => "raw"}, loaded_socket)

    raw_html =
      raw_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert raw_html =~ "&quot;dynamic_work&quot;"
    assert raw_html =~ "&quot;dynamic_work_overlays&quot;"
    assert raw_html =~ "capture_payment:dynamic:fraud_review"
  end

  test "renders deferred continuation inspection and raw facts" do
    visible_at = ~U[2026-05-15 10:45:00Z]
    deferred_at = ~U[2026-05-15 10:15:00Z]

    deferred_attempt = %{
      step: "capture_payment",
      status: :retry_scheduled,
      attempt_number: 2,
      runnable_key: "run-deferred-live:capture_payment:2",
      visible_at: visible_at,
      deferred: %{
        reason: %{
          message: :awaiting_provider,
          target: %{step: :capture_payment, branch: :provider_callback},
          context: %{decision: :hold, provider_reference: "pi_123"}
        },
        deferred_at: deferred_at,
        from_runnable_key: "run-deferred-live:capture_payment:1",
        wakeup: %{visible_at: visible_at}
      }
    }

    snapshot =
      snapshot(:running,
        run_id: "run-deferred-live",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :deferred_continuation,
        scheduled_attempts: [deferred_attempt],
        next_visible_at: visible_at
      )

    graph =
      graph_inspection(:running,
        run_id: "run-deferred-live",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("load_order", :completed, false),
          graph_node("capture_payment", :deferred, true),
          graph_node("send_receipt", :waiting, false)
        ],
        edges: [
          graph_edge("load_order", "capture_payment", :ok),
          graph_edge("capture_payment", "send_receipt", :ok)
        ]
      )

    explanation =
      diagnostic(:running,
        run_id: "run-deferred-live",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :deferred_continuation,
        step: "capture_payment",
        summary: "A workflow step deferred its continuation.",
        next_actions: [:wait_until_attempt_visible],
        details: %{
          deferred_attempt_count: 1,
          next_visible_at: visible_at,
          deferred: [
            %{
              reason: :awaiting_provider,
              target: %{step: :capture_payment, branch: :provider_callback},
              context: %{decision: :hold, provider_reference: "pi_123"}
            }
          ]
        }
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-deferred-live"},
        "/kansoku/runs/run-deferred-live",
        mounted_socket
      )

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Deferred continuations"
    assert html =~ "safe cancellation and replay guidance"
    assert html =~ "capture_payment"
    assert html =~ "reason awaiting provider"
    assert html =~ "target capture_payment"
    assert html =~ "branch provider_callback"
    assert html =~ "visible 2026-05-15T10:45:00Z"
    assert html =~ "deferred 2026-05-15T10:15:00Z"
    assert html =~ "context decision, provider reference"
    assert html =~ "wait_until_attempt_visible"
    assert html =~ "kansoku-workflow-node-deferred"
    assert html =~ "deferred"

    {:noreply, raw_socket} =
      RunLive.handle_event("select_workflow_panel", %{"view" => "raw"}, loaded_socket)

    raw_html =
      raw_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert raw_html =~ "&quot;deferred_continuations&quot;"
    assert raw_html =~ "awaiting_provider"
    assert raw_html =~ "pi_123"
  end

  test "renders recovery policy diagnostics when present" do
    recovery = compensation_recovery("ReleaseInventory")

    graph =
      graph_inspection(:failed,
        run_id: "run-recovery-summary",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("reserve_inventory", :completed, false, recovery: recovery),
          graph_node("capture_payment", :failed, true)
        ],
        edges: [
          graph_edge("reserve_inventory", "capture_payment", :ok)
        ]
      )

    snapshot =
      snapshot(:failed,
        run_id: "run-recovery-summary",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "capture_payment",
        reason: :terminal
      )

    explanation =
      diagnostic(:failed,
        run_id: "run-recovery-summary",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :terminal,
        step: "capture_payment",
        evidence:
          recovery_policy_evidence(%{
            reserve_inventory: recovery,
            capture_payment: %{
              irreversible?: true,
              compensatable?: false,
              replay: :manual_review_required,
              recovery: :manual_intervention,
              input: %{card_token: "tok_secret"}
            }
          })
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-recovery-summary"},
        "/kansoku/runs/run-recovery-summary",
        mounted_socket
      )

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Compensation evidence"
    assert html =~ "Read-only rollback and undo evidence"
    assert html =~ "reserve_inventory"
    assert html =~ "ReleaseInventory"
    assert html =~ "available"
    assert html =~ "capture_payment"
    assert html =~ "irreversible"
    assert html =~ "manual review required"
    assert html =~ "manual intervention"
    refute html =~ "tok_secret"
  end

  test "renders compensation failure evidence near the graph and detail panels" do
    recovery = compensation_recovery("ReleaseInventory")

    graph =
      graph_inspection(:failed,
        run_id: "run-compensation-evidence",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "compensate:reserve_inventory",
        nodes: [
          graph_node("reserve_inventory", :completed, false, recovery: recovery),
          graph_node("fail_payment", :failed, false),
          graph_node("compensate:reserve_inventory", :failed, true)
        ],
        edges: [
          graph_edge("reserve_inventory", "fail_payment", :ok),
          graph_edge("fail_payment", "compensate:reserve_inventory", :error,
            recovery: :compensation
          )
        ]
      )

    snapshot =
      snapshot(:failed,
        run_id: "run-compensation-evidence",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_step: "compensate:reserve_inventory",
        reason: :terminal,
        attempts: [
          attempt("reserve_inventory", :completed, 1, nil, recovery: recovery),
          attempt("fail_payment", :failed, 1, %{"message" => "gateway unavailable"}),
          attempt("compensate:reserve_inventory", :failed, 1, %{
            "message" => "release failed for token tok_secret",
            "customer" => "cust_secret"
          })
        ]
      )

    explanation =
      diagnostic(:failed,
        run_id: "run-compensation-evidence",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :terminal,
        step: "compensate:reserve_inventory",
        next_actions: [:inspect_compensation_failure, :manual_intervention],
        evidence:
          recovery_policy_evidence(%{
            reserve_inventory: recovery,
            fail_payment: %{
              irreversible?: true,
              compensatable?: false,
              recovery: :manual_intervention
            }
          })
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-compensation-evidence"},
        "/kansoku/runs/run-compensation-evidence",
        mounted_socket
      )

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Compensation evidence"
    assert html =~ "reserve_inventory"
    assert html =~ "ReleaseInventory"
    assert html =~ "compensation failed"
    assert html =~ "reason present"
    assert html =~ "fail_payment"
    assert html =~ "irreversible"
    assert html =~ "non-compensatable"
    assert html =~ "inspect_compensation_failure"
    assert html =~ "kansoku-workflow-node-compensation"
    refute html =~ "gateway unavailable"
    refute html =~ "tok_secret"
    refute html =~ "cust_secret"
  end

  test "does not render an empty recovery policy section" do
    FakeJizokuClient.put_inspect_run(
      {:ok,
       snapshot(:running, run_id: "run-no-recovery", workflow: Atom.to_string(CheckoutWorkflow))}
    )

    FakeJizokuClient.put_inspect_run_graph(
      {:ok,
       graph_inspection(:running,
         run_id: "run-no-recovery",
         workflow: Atom.to_string(CheckoutWorkflow)
       )}
    )

    FakeJizokuClient.put_explain_run(
      {:ok,
       diagnostic(:running,
         run_id: "run-no-recovery",
         workflow: Atom.to_string(CheckoutWorkflow)
       )}
    )

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-no-recovery"}, "", mounted_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    refute html =~ "Compensation evidence"
    refute html =~ "Read-only rollback and undo evidence"
  end

  test "renders load errors without leaking internal reason details" do
    FakeJizokuClient.put_inspect_run({:error, {:missing_config, [:repo]}})

    FakeJizokuClient.put_cancel(fn _run_id, _opts ->
      send(self(), :cancel_called)
      {:error, :must_not_run}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "bad"}, "/kansoku/runs/bad", mounted_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Unable to load runs"
    refute html =~ "missing_config"

    assert {:noreply, denied_socket} =
             RunLive.handle_event("cancel", %{"run-id" => "bad"}, loaded_socket)

    refute_received :cancel_called
    assert denied_socket.assigns.control_flash["error"] == "Run controls are not authorized."
  end

  test "keeps operator run details redacted while allowing control events" do
    snapshot =
      snapshot(:paused,
        run_id: "restricted-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        input: %{"secret" => "snapshot-secret"},
        context: %{"secret" => "context-secret"},
        terminal?: false,
        manual_state: %{kind: "approval", step: "review_order", reason: "review"}
      )

    graph =
      graph_inspection(:paused,
        run_id: "restricted-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "review_order",
        nodes: [
          graph_node("review_order", :paused, true,
            input: %{"secret" => "graph-secret"},
            output: %{"secret" => "output-secret"}
          )
        ]
      )

    explanation =
      diagnostic(:paused,
        run_id: "restricted-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        step: "review_order",
        details: %{kind: "approval", secret: "diagnostic-secret"},
        next_actions: [:resolve_manual_step],
        evidence: %{manual_state: %{kind: "approval"}, secret: "evidence-secret"}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    FakeJizokuClient.put_approve(fn _run_id, _attrs, _opts ->
      send(self(), :approve_called)
      {:ok, snapshot}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    restricted_socket =
      mounted_socket
      |> Phoenix.Component.assign(:visibility_actor, "operator-1")
      |> Phoenix.Component.assign(:visibility_policy, :operator)

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "restricted-run"},
        "/kansoku/runs/restricted-run",
        restricted_socket
      )

    rendered = RunLive.render(loaded_socket.assigns)
    html = rendered_to_string(rendered)

    refute html =~ "snapshot-secret"
    refute html =~ "context-secret"
    refute html =~ "graph-secret"
    refute html =~ "output-secret"
    refute html =~ "diagnostic-secret"
    refute html =~ "evidence-secret"
    assert html =~ ~s(id="run-summary-json")
    assert html =~ ~s(data-copy-target="run-summary-json")
    assert html =~ "&quot;thread_revisions&quot;"
    refute html =~ "&quot;terminal&quot;"
    refute html =~ "&quot;terminal_status&quot;"
    assert html =~ ~s(phx-click="approve")
    assert html =~ ~s(phx-click="reject")
    assert html =~ ~s(phx-click="cancel")

    {:noreply, raw_socket} = RunLive.handle_event("show_raw_workflow_panel", %{}, loaded_socket)
    raw_html = rendered_to_string(RunLive.render(raw_socket.assigns))

    assert raw_html =~ ~s(data-copy-target="run-graph-json")
    refute raw_html =~ "graph-secret"
    refute raw_html =~ "output-secret"

    assert {:noreply, approved_socket} =
             RunLive.handle_event("approve", %{"run-id" => "restricted-run"}, loaded_socket)

    assert_received :approve_called
    assert approved_socket.assigns.control_flash["info"] == "Run approved successfully"
  end

  test "keeps auditor run controls read-only" do
    snapshot =
      snapshot(:paused,
        run_id: "auditor-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        terminal?: false,
        manual_state: %{kind: "approval", step: "review_order", reason: "review"}
      )

    graph =
      graph_inspection(:paused,
        run_id: "auditor-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "review_order",
        nodes: [graph_node("review_order", :paused, true)]
      )

    explanation =
      diagnostic(:paused,
        run_id: "auditor-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        step: "review_order",
        details: %{kind: "approval"},
        next_actions: [:resolve_manual_step],
        evidence: %{manual_state: %{kind: "approval"}}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    FakeJizokuClient.put_approve(fn _run_id, _attrs, _opts ->
      send(self(), :approve_called)
      {:ok, snapshot}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    auditor_socket =
      mounted_socket
      |> Phoenix.Component.assign(:visibility_actor, "auditor-1")
      |> Phoenix.Component.assign(:visibility_policy, :auditor)

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "auditor-run"}, "/kansoku/runs/auditor-run", auditor_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    refute html =~ ~s(phx-click="approve")
    refute html =~ ~s(phx-click="reject")
    refute html =~ ~s(phx-click="cancel")

    assert {:noreply, denied_socket} =
             RunLive.handle_event("approve", %{"run-id" => "auditor-run"}, loaded_socket)

    refute_received :approve_called
    assert denied_socket.assigns.control_flash["error"] == "Run controls are not authorized."
  end

  test "rejects a control event targeting a different run" do
    snapshot =
      snapshot(:running,
        run_id: "authorized-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        terminal?: false
      )

    graph =
      graph_inspection(:running,
        run_id: "authorized-run",
        workflow: Atom.to_string(CheckoutWorkflow)
      )

    explanation =
      diagnostic(:running,
        run_id: "authorized-run",
        workflow: Atom.to_string(CheckoutWorkflow)
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    FakeJizokuClient.put_cancel(fn _run_id, _opts ->
      send(self(), :cancel_called)
      {:ok, snapshot}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "authorized-run"},
        "/kansoku/runs/authorized-run",
        operator_socket(mounted_socket)
      )

    assert {:noreply, denied_socket} =
             RunLive.handle_event("cancel", %{"run-id" => "other-run"}, loaded_socket)

    refute_received :cancel_called
    assert denied_socket.assigns.control_flash["error"] == "Run controls are not authorized."
  end

  defp operator_socket(socket) do
    Phoenix.Component.assign(socket, :visibility_policy, :operator)
  end

  defp put_basic_run(run_id) do
    workflow = Atom.to_string(CheckoutWorkflow)

    FakeJizokuClient.put_inspect_run(
      {:ok,
       snapshot(:running,
         run_id: run_id,
         workflow: workflow,
         current_step: "capture_payment",
         reason: :attempt_visible
       )}
    )

    FakeJizokuClient.put_inspect_run_graph(
      {:ok,
       graph_inspection(:running,
         run_id: run_id,
         workflow: workflow,
         current_node_id: "capture_payment",
         nodes: [graph_node("capture_payment", :running, true)]
       )}
    )

    FakeJizokuClient.put_explain_run(
      {:ok,
       diagnostic(:running,
         run_id: run_id,
         workflow: workflow,
         step: "capture_payment",
         reason: :attempt_visible
       )}
    )
  end

  defp timeline(run_id, events) do
    %Timeline{
      run_id: run_id,
      workflow: Atom.to_string(CheckoutWorkflow),
      queue: "default",
      status: :running,
      terminal?: false,
      terminal_status: nil,
      events: events
    }
  end
end
