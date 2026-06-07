defmodule SquidSonarWeb.RunLiveTest do
  use ExUnit.Case, async: false

  import SquidSonar.ReadModelFixtures

  defmodule CheckoutWorkflow do
    use Squidie.Workflow

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

  alias Phoenix.LiveView.Socket
  alias SquidSonar.FakeSquidieClient
  alias SquidSonarWeb.RunLive

  setup do
    previous_client = Application.get_env(:squid_sonar, :squidie_client)
    Application.put_env(:squid_sonar, :squidie_client, FakeSquidieClient)

    on_exit(fn ->
      if previous_client do
        Application.put_env(:squid_sonar, :squidie_client, previous_client)
      else
        Application.delete_env(:squid_sonar, :squidie_client)
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-1"}, "/sonar/runs/run-1", mounted_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "SquidSonar"
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
    assert html =~ "squid-sonar-workflow-graph"
    assert html =~ "squid-sonar-workflow-node-deadline"
    assert html =~ "squid-sonar-workflow-panel-actions"
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-live-claims"},
        "/sonar/runs/run-live-claims",
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    FakeSquidieClient.put_cancel(
      {:ok, snapshot(:cancelled, run_id: "run-1", workflow: Atom.to_string(CheckoutWorkflow))}
    )

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-1"}, "/sonar/runs/run-1", mounted_socket)

    {:noreply, cancelled_socket} =
      RunLive.handle_event("cancel", %{"run-id" => "run-1"}, loaded_socket)

    feedback_html =
      cancelled_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert feedback_html =~ "Run cancelled successfully"
    assert feedback_html =~ "phx-hook=\"SquidSonarFlash\""
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

    FakeSquidieClient.put_inspect_run(fn
      "run-approval", _opts ->
        count = Process.get(:refresh_run_inspections, 0)
        Process.put(:refresh_run_inspections, count + 1)

        case count do
          0 -> {:ok, initial_snapshot}
          1 -> {:ok, running_snapshot}
          _count -> {:ok, completed_snapshot}
        end
    end)

    FakeSquidieClient.put_inspect_run_graph(fn run_id, _opts ->
      {:ok,
       graph_inspection(:running,
         run_id: run_id,
         workflow: Atom.to_string(CheckoutWorkflow),
         current_node_id: "record_approval",
         nodes: [graph_node("record_approval", :running, true)]
       )}
    end)

    FakeSquidieClient.put_explain_run(fn run_id, _opts ->
      {:ok,
       diagnostic(:running,
         run_id: run_id,
         workflow: Atom.to_string(CheckoutWorkflow),
         reason: :attempt_visible,
         step: "record_approval",
         next_actions: [:wait_for_worker_claim]
       )}
    end)

    FakeSquidieClient.put_approve({:ok, running_snapshot})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-approval"}, "/sonar/runs/run-approval", mounted_socket)

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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-approval"}, "/sonar/runs/run-approval", mounted_socket)

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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    FakeSquidieClient.put_approve(fn run_id, attrs, _opts ->
      send(parent, {:approve_attrs, run_id, attrs})
      {:ok, snapshot(:running, run_id: run_id, workflow: Atom.to_string(CheckoutWorkflow))}
    end)

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})
    actor_socket = Phoenix.Component.assign(mounted_socket, :control_actor, actor)

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-approval"}, "/sonar/runs/run-approval", actor_socket)

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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})
    FakeSquidieClient.put_cancel({:error, {:missing_config, [:repo]}})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-1"}, "/sonar/runs/run-1", mounted_socket)

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

    FakeSquidieClient.put_inspect_run(fn
      "run-1", _opts -> {:ok, source_snapshot}
      "run-2", _opts -> {:ok, replayed_snapshot}
    end)

    FakeSquidieClient.put_inspect_run_graph(fn
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

    FakeSquidieClient.put_explain_run(fn
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
      RunLive.handle_params(%{"id" => "run-1"}, "/sonar/runs/run-1", mounted_socket)

    FakeSquidieClient.put_replay({:ok, replayed_snapshot})

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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "run-history"}, "/sonar/runs/run-history", mounted_socket)

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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-raw-graph"},
        "/sonar/runs/run-raw-graph",
        mounted_socket
      )

    assert loaded_socket.assigns.detail.explanation.evidence ==
             recovery_policy_evidence("capture_payment", recovery)

    visual_html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert visual_html =~ "Transition graph"
    assert visual_html =~ "Raw inspection"
    assert visual_html =~ "Rollback"
    assert visual_html =~ "squid-sonar-workflow-node-recovery-panel"
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-dynamic-work"},
        "/sonar/runs/run-dynamic-work",
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
    assert html =~ "squid-sonar-workflow-node-dynamic"
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-deferred-live"},
        "/sonar/runs/run-deferred-live",
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
    assert html =~ "squid-sonar-workflow-node-deferred"
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-recovery-summary"},
        "/sonar/runs/run-recovery-summary",
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

    FakeSquidieClient.put_inspect_run({:ok, snapshot})
    FakeSquidieClient.put_inspect_run_graph({:ok, graph})
    FakeSquidieClient.put_explain_run({:ok, explanation})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(
        %{"id" => "run-compensation-evidence"},
        "/sonar/runs/run-compensation-evidence",
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
    assert html =~ "squid-sonar-workflow-node-compensation"
    refute html =~ "gateway unavailable"
    refute html =~ "tok_secret"
    refute html =~ "cust_secret"
  end

  test "does not render an empty recovery policy section" do
    FakeSquidieClient.put_inspect_run(
      {:ok,
       snapshot(:running, run_id: "run-no-recovery", workflow: Atom.to_string(CheckoutWorkflow))}
    )

    FakeSquidieClient.put_inspect_run_graph(
      {:ok,
       graph_inspection(:running,
         run_id: "run-no-recovery",
         workflow: Atom.to_string(CheckoutWorkflow)
       )}
    )

    FakeSquidieClient.put_explain_run(
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
    FakeSquidieClient.put_inspect_run({:error, {:missing_config, [:repo]}})

    {:ok, mounted_socket} = RunLive.mount(%{}, %{}, %Socket{})

    {:noreply, loaded_socket} =
      RunLive.handle_params(%{"id" => "bad"}, "/sonar/runs/bad", mounted_socket)

    html =
      loaded_socket.assigns
      |> RunLive.render()
      |> rendered_to_string()

    assert html =~ "Unable to load runs"
    refute html =~ "missing_config"
  end
end
