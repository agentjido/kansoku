defmodule Kansoku.RunsTest do
  use ExUnit.Case, async: true

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

  defmodule AccountWorkflow do
    use Jizoku.Workflow

    workflow do
      trigger :manual do
        manual()

        payload do
          field(:account_id, :string)
        end
      end

      step(:load_account, :log, message: "load account")
      transition(:load_account, on: :ok, to: :complete)
    end
  end

  defmodule ReleaseInventory do
    use Jizoku.Step,
      name: :release_inventory,
      input_schema: [
        step: [type: :map, required: true]
      ]

    @impl Jizoku.Step
    def run(_input, _context), do: {:ok, %{}}
  end

  defmodule CompensatingWorkflow do
    use Jizoku.Workflow

    workflow do
      trigger :manual do
        manual()
      end

      step(:reserve_inventory, :log,
        message: "reserve inventory",
        compensate: ReleaseInventory
      )

      step(:capture_payment, :log, message: "capture payment")

      transition(:reserve_inventory, on: :ok, to: :capture_payment)
      transition(:capture_payment, on: :ok, to: :complete)
    end
  end

  defmodule DependencyWorkflow do
    use Jizoku.Workflow

    workflow do
      trigger :manual do
        manual()
      end

      step(:load_account, :log, message: "load account")
      step(:load_invoice, :log, message: "load invoice", after: [:load_account])
      step(:send_email, :log, message: "send email", after: [:load_account, :load_invoice])
    end
  end

  defmodule MissingWorkflow do
  end

  defmodule LegacyTimelineClient do
    @spec inspect_run(term(), keyword()) ::
            {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
    def inspect_run(run_id, opts), do: Kansoku.FakeJizokuClient.inspect_run(run_id, opts)

    @spec inspect_run_graph(term(), keyword()) ::
            {:ok, Jizoku.Runs.GraphInspection.t()} | {:error, term()}
    def inspect_run_graph(run_id, opts),
      do: Kansoku.FakeJizokuClient.inspect_run_graph(run_id, opts)

    @spec explain_run(term(), keyword()) ::
            {:ok, Jizoku.ReadModel.Explanation.Diagnostic.t()} | {:error, term()}
    def explain_run(run_id, opts), do: Kansoku.FakeJizokuClient.explain_run(run_id, opts)
  end

  alias Jizoku.ReadModel.Listing.Summary
  alias Kansoku.FakeJizokuClient
  alias Kansoku.Runs
  alias Kansoku.Runs.RunDetail
  alias Kansoku.Runs.RunSummary

  test "run detail projections deny controls unless explicitly authorized" do
    snapshot = snapshot(:running, workflow: Atom.to_string(CheckoutWorkflow))
    graph = graph_inspection(:running, workflow: Atom.to_string(CheckoutWorkflow))
    explanation = diagnostic(:running, workflow: Atom.to_string(CheckoutWorkflow))

    assert %RunDetail{controls_allowed?: false} =
             RunDetail.from_models(snapshot, explanation, graph)
  end

  @client FakeJizokuClient
  @now ~U[2026-05-15 10:00:00Z]

  test "lists run summaries through the configured client" do
    FakeJizokuClient.put_list_runs(
      {:ok,
       [
         summary(:running, workflow: Atom.to_string(CheckoutWorkflow), queue: "default"),
         summary(:failed, workflow: Atom.to_string(DependencyWorkflow), queue: "priority")
       ]}
    )

    assert {:ok, [%RunSummary{} = first, %RunSummary{} = second]} =
             Runs.list_runs([status: :running], client: @client)

    assert first.id == "run-running"
    assert first.workflow == Atom.to_string(CheckoutWorkflow)
    assert first.queue == "default"
    assert first.status == :running

    assert second.id == "run-failed"
    assert second.workflow == Atom.to_string(DependencyWorkflow)
    assert second.queue == "priority"
    assert second.status == :failed
  end

  test "projects deadline state from run summaries" do
    deadline = %{
      status: :overdue,
      step: "capture_payment",
      due_at: ~U[2026-05-15 10:15:00Z],
      escalation: %{outcome: :diagnostic}
    }

    FakeJizokuClient.put_list_runs(
      {:ok,
       [
         summary(:running,
           workflow: Atom.to_string(CheckoutWorkflow),
           deadline: deadline
         )
       ]}
    )

    assert {:ok, [%RunSummary{} = run]} = Runs.list_runs([], client: @client)

    assert run.deadline == deadline
  end

  test "returns client list errors unchanged" do
    FakeJizokuClient.put_list_runs({:error, {:missing_config, [:repo]}})

    assert {:error, {:missing_config, [:repo]}} =
             Runs.list_runs([], client: @client)
  end

  test "starts a runtime-authored spec through the host action registry boundary" do
    spec = runtime_spec()
    payload = %{"order_id" => "order-1"}
    normalized_payload = %{order_id: "order-1"}
    registry = %{"load_order" => CheckoutWorkflow}

    FakeJizokuClient.put_start_spec(fn started_spec, started_payload, opts ->
      send(self(), {:start_spec, started_spec, started_payload, opts})

      {:ok,
       snapshot(:running,
         run_id: "runtime-spec-run",
         workflow: "RuntimeCheckout",
         reason: :attempt_visible
       )}
    end)

    assert {:ok, started_run} =
             Runs.start_spec(spec, payload,
               client: @client,
               jizoku: [queue: "critical"],
               action_registry: registry
             )

    assert started_run.run_id == "runtime-spec-run"

    assert_received {:start_spec, ^spec, ^normalized_payload,
                     [queue: "critical", action_registry: ^registry]}
  end

  test "starts a DSL workflow through the workflow boundary" do
    payload = %{"account_id" => "acct-1"}

    FakeJizokuClient.put_start(fn workflow, started_payload, opts ->
      send(self(), {:start_workflow, workflow, started_payload, opts})

      {:ok,
       snapshot(:running,
         run_id: "workflow-run",
         workflow: Atom.to_string(workflow),
         reason: :attempt_visible
       )}
    end)

    assert {:ok, started_run} =
             Runs.start_workflow(AccountWorkflow, payload,
               client: @client,
               jizoku: [queue: "critical"]
             )

    assert started_run.run_id == "workflow-run"

    assert_received {:start_workflow, AccountWorkflow, %{account_id: "acct-1"},
                     [queue: "critical"]}
  end

  test "returns runtime spec start errors unchanged" do
    FakeJizokuClient.put_start_spec({:error, {:invalid_payload, :expected_map}})

    assert {:error, {:invalid_payload, :expected_map}} =
             Runs.start_spec(runtime_spec(), "not-a-map", client: @client)
  end

  test "gets run detail with journal evidence and explanation" do
    deadline = %{
      status: :escalated,
      step: "capture_payment",
      due_at: ~U[2026-05-15 10:15:00Z],
      due_soon_at: ~U[2026-05-15 10:10:00Z],
      escalated_at: ~U[2026-05-15 10:16:00Z],
      escalation: %{outcome: :diagnostic}
    }

    snapshot =
      snapshot(:running,
        run_id: "run-2",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        current_step: "capture_payment",
        deadline: deadline,
        attempts: [
          attempt("capture_payment", :claimed, 1, %{"message" => "gateway unavailable"},
            deadline: deadline
          )
        ],
        planned_runnables: [%{runnable_key: "capture_payment"}],
        anomalies: [%{kind: :stale_projection}]
      )

    graph =
      graph_inspection(:running,
        run_id: "run-2",
        workflow: Atom.to_string(CheckoutWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("load_order", :completed, false),
          graph_node("capture_payment", :running, true,
            deadline: deadline,
            recovery: compensation_recovery("ReleaseInventory")
          ),
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
        run_id: "run-2",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment",
        summary: "A dispatch attempt is visible and waiting for a worker claim.",
        details: %{
          visible_attempt_count: 1,
          runnable_keys: ["capture_payment"],
          deadline_status: :escalated,
          deadline_escalation: %{outcome: :diagnostic}
        },
        next_actions: [:wait_for_worker_claim, :apply_host_escalation_policy],
        evidence: %{attempt_counts: %{claimed: 1}, deadline: deadline}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:ok, %RunDetail{} = detail} = Runs.get_run("run-2", client: @client)

    assert detail.summary.id == "run-2"
    assert detail.summary.workflow == Atom.to_string(CheckoutWorkflow)
    assert detail.summary.queue == "default"
    assert detail.summary.status == :running
    assert detail.summary.current_step == "capture_payment"
    assert detail.summary.reason == :attempt_visible
    assert detail.summary.deadline == deadline
    assert detail.summary.thread_revisions == %{run: 3, dispatch: 4}

    assert detail.payload == %{"order_id" => "order-1"}
    assert detail.context == %{"attempted" => true}
    assert detail.last_error == %{"message" => "gateway unavailable"}
    assert detail.planned_runnables == [%{runnable_key: "capture_payment"}]
    assert [_attempt] = detail.attempts
    assert [_anomaly] = detail.anomalies
    assert detail.explanation.summary =~ "waiting for a worker claim"

    assert Enum.map(detail.workflow_graph.nodes, & &1.name) == [
             "load_order",
             "capture_payment",
             "send_receipt"
           ]

    capture_node = Enum.find(detail.workflow_graph.nodes, &(&1.name == "capture_payment"))

    assert capture_node.deadline == deadline
    assert capture_node.recovery == compensation_recovery("ReleaseInventory")

    assert Enum.map(detail.workflow_graph.edges, &{&1.from, &1.to, &1.outcome}) == [
             {"load_order", "capture_payment", :ok},
             {"capture_payment", "send_receipt", :ok}
           ]
  end

  test "adds definition recovery metadata when graph nodes omit it" do
    snapshot =
      snapshot(:failed,
        run_id: "run-recovery-definition",
        workflow: Atom.to_string(CompensatingWorkflow),
        reason: :terminal,
        current_step: "capture_payment"
      )

    graph =
      graph_inspection(:failed,
        run_id: "run-recovery-definition",
        workflow: Atom.to_string(CompensatingWorkflow),
        current_node_id: "capture_payment",
        nodes: [
          graph_node("reserve_inventory", :completed, false),
          graph_node("capture_payment", :failed, true)
        ],
        edges: [
          graph_edge("reserve_inventory", "capture_payment", :ok)
        ]
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})

    FakeJizokuClient.put_explain_run(
      {:ok,
       diagnostic(:failed,
         run_id: "run-recovery-definition",
         workflow: Atom.to_string(CompensatingWorkflow)
       )}
    )

    assert {:ok, %RunDetail{} = detail} =
             Runs.get_run("run-recovery-definition", client: @client)

    assert Enum.find(detail.workflow_graph.nodes, &(&1.name == "reserve_inventory")).recovery ==
             %{
               compensation: %{
                 callback: ReleaseInventory,
                 status: :available
               }
             }

    assert Enum.find(detail.workflow_graph.nodes, &(&1.name == "capture_payment")).recovery == nil
  end

  test "marks snapshot timelines partial for legacy clients without the timeline callback" do
    run_id = "run-legacy-timeline"
    workflow = Atom.to_string(CheckoutWorkflow)

    FakeJizokuClient.put_inspect_run(
      {:ok, snapshot(:running, run_id: run_id, workflow: workflow)}
    )

    FakeJizokuClient.put_inspect_run_graph(
      {:ok, graph_inspection(:running, run_id: run_id, workflow: workflow)}
    )

    FakeJizokuClient.put_explain_run(
      {:ok, diagnostic(:running, run_id: run_id, workflow: workflow)}
    )

    assert {:ok, detail} = Runs.get_run(run_id, client: LegacyTimelineClient)
    assert detail.timeline.run_id == run_id
    assert detail.timeline_partial?
  end

  test "rejects a timeline returned for a different run" do
    run_id = "run-requested-timeline"
    workflow = Atom.to_string(CheckoutWorkflow)

    FakeJizokuClient.put_inspect_run(
      {:ok, snapshot(:running, run_id: run_id, workflow: workflow)}
    )

    FakeJizokuClient.put_inspect_run_graph(
      {:ok, graph_inspection(:running, run_id: run_id, workflow: workflow)}
    )

    FakeJizokuClient.put_explain_run(
      {:ok, diagnostic(:running, run_id: run_id, workflow: workflow)}
    )

    FakeJizokuClient.put_inspect_run_timeline(
      {:ok,
       %Jizoku.ReadModel.Timeline{
         run_id: "run-other-timeline",
         workflow: workflow,
         queue: "default",
         status: :running,
         terminal?: false,
         terminal_status: nil,
         events: []
       }}
    )

    assert {:ok, detail} = Runs.get_run(run_id, client: @client)
    assert detail.timeline.run_id == run_id
    assert detail.timeline_partial?
  end

  test "redacts every run detail read model before projection" do
    snapshot =
      snapshot(:running,
        run_id: "restricted-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        input: %{"secret" => "snapshot-secret"},
        context: %{"secret" => "context-secret"},
        attempts: [attempt("load_order", :failed, 1, %{"message" => "attempt-secret"})]
      )

    graph =
      graph_inspection(:running,
        run_id: "restricted-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        nodes: [
          graph_node("load_order", :running, true,
            input: %{"secret" => "graph-secret"},
            output: %{"secret" => "output-secret"}
          )
        ]
      )

    explanation =
      diagnostic(:running,
        run_id: "restricted-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        details: %{secret: "diagnostic-secret"},
        evidence: %{secret: "evidence-secret"}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:ok, detail} =
             Runs.get_run("restricted-run",
               client: @client,
               visibility_actor: "operator-1",
               visibility_policy: :operator,
               controls_allowed?: false
             )

    assert detail.payload == nil
    assert detail.context == %{}
    assert detail.last_error == nil
    assert detail.controls_allowed? == false
    refute inspect(detail) =~ "snapshot-secret"
    refute inspect(detail) =~ "context-secret"
    refute inspect(detail) =~ "attempt-secret"
    refute inspect(detail) =~ "graph-secret"
    refute inspect(detail) =~ "output-secret"
    refute inspect(detail) =~ "diagnostic-secret"
    refute inspect(detail) =~ "evidence-secret"
  end

  test "preserves full run detail for an explicit auditor" do
    snapshot =
      snapshot(:running,
        run_id: "auditor-run",
        workflow: Atom.to_string(CheckoutWorkflow),
        input: %{"visible" => "auditor-value"}
      )

    graph =
      graph_inspection(:running,
        run_id: "auditor-run",
        workflow: Atom.to_string(CheckoutWorkflow)
      )

    explanation =
      diagnostic(:running,
        run_id: "auditor-run",
        workflow: Atom.to_string(CheckoutWorkflow)
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:ok, detail} =
             Runs.get_run("auditor-run",
               client: @client,
               visibility_actor: "auditor-1",
               visibility_policy: :auditor,
               controls_allowed?: true
             )

    assert detail.payload == %{"visible" => "auditor-value"}
    assert detail.controls_allowed? == true
  end

  test "fails closed when the run detail visibility policy is invalid" do
    snapshot = snapshot(:running, workflow: Atom.to_string(CheckoutWorkflow))
    graph = graph_inspection(:running, workflow: Atom.to_string(CheckoutWorkflow))
    explanation = diagnostic(:running, workflow: Atom.to_string(CheckoutWorkflow))

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:error, {:invalid_visibility_policy, :missing_callback}} =
             Runs.get_run("run-running",
               client: @client,
               visibility_actor: "operator-1",
               visibility_policy: __MODULE__
             )
  end

  test "projects dynamic work overlays and graph metadata" do
    origin = %{step: "capture_payment", branch: "fraud_review"}
    recorded_at = ~U[2026-05-15 10:17:00Z]

    dynamic_work = [
      %{
        dynamic_key: "fraud_review",
        status: :recorded,
        reason: :risk_signal,
        origin: origin,
        nodes: [
          %{
            id: "fraud_review",
            action: "review_risk",
            status: :scheduled,
            metadata: %{queue: "risk"}
          }
        ],
        edges: [
          %{
            id: "capture_payment:dynamic:fraud_review",
            from: "capture_payment",
            to: "fraud_review"
          }
        ],
        recorded_at: recorded_at
      },
      %{nodes: "stale"}
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
            dynamic_key: "fraud_review",
            status: :recorded,
            reason: :risk_signal,
            origin: origin,
            origin_node_id: "capture_payment",
            added_node_ids: ["fraud_review"],
            added_edge_ids: ["capture_payment:dynamic:fraud_review"],
            node_count: 1,
            edge_count: 1,
            recorded_at: recorded_at
          },
          %{}
        ]
    }

    snapshot =
      snapshot(:running,
        run_id: "run-dynamic-work",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        current_step: "capture_payment"
      )

    explanation =
      diagnostic(:running,
        run_id: "run-dynamic-work",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :attempt_visible,
        step: "capture_payment"
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:ok, %RunDetail{} = detail} = Runs.get_run("run-dynamic-work", client: @client)

    assert [
             %RunDetail.DynamicWorkOverlay{
               dynamic_key: "fraud_review",
               status: :recorded,
               reason: :risk_signal,
               origin_node_id: "capture_payment",
               added_node_ids: ["fraud_review"],
               added_edge_ids: ["capture_payment:dynamic:fraud_review"],
               node_count: 1,
               edge_count: 1,
               recorded_at: ^recorded_at
             }
           ] = detail.dynamic_work_overlays

    assert detail.dynamic_work == dynamic_work
    assert detail.graph_inspection.dynamic_work == dynamic_work
    assert detail.graph_inspection.dynamic_work_overlays != []

    dynamic_node = Enum.find(detail.workflow_graph.nodes, &(&1.name == "fraud_review"))
    assert dynamic_node.dynamic?
    assert dynamic_node.origin == origin
    assert dynamic_node.metadata == %{queue: "risk"}

    assert [%{type: :dynamic, status: :pending}] = detail.workflow_graph.edges
  end

  test "projects safe recovery policy diagnostics from explanation evidence" do
    reserve_recovery = compensation_recovery("ReleaseInventory")

    policies =
      recovery_policy_evidence(%{
        reserve_inventory: reserve_recovery,
        capture_payment: %{
          irreversible?: true,
          compensatable?: false,
          replay: :manual_review_required,
          recovery: :manual_intervention,
          input: %{card_token: "tok_secret"},
          output: %{charge_id: "ch_sensitive"}
        },
        send_receipt: %{
          irreversible?: false,
          compensatable?: false,
          replay: :manual_review_required,
          recovery: :manual_intervention,
          idempotency_key: "receipt-secret"
        }
      })

    snapshot =
      snapshot(:failed,
        run_id: "run-recovery-policies",
        workflow: Atom.to_string(CheckoutWorkflow),
        reason: :terminal
      )

    graph =
      graph_inspection(:failed,
        run_id: "run-recovery-policies",
        workflow: Atom.to_string(CheckoutWorkflow)
      )

    explanation =
      diagnostic(:failed,
        run_id: "run-recovery-policies",
        workflow: Atom.to_string(CheckoutWorkflow),
        evidence: policies
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:ok, %RunDetail{} = detail} =
             Runs.get_run("run-recovery-policies", client: @client)

    assert detail.recovery_policies == [
             %RunDetail.RecoveryPolicy{
               step: "capture_payment",
               compensation_callback: nil,
               compensation_status: nil,
               irreversible?: true,
               compensatable?: false,
               replay: :manual_review_required,
               recovery: :manual_intervention
             },
             %RunDetail.RecoveryPolicy{
               step: "reserve_inventory",
               compensation_callback: "ReleaseInventory",
               compensation_status: :available,
               irreversible?: nil,
               compensatable?: nil,
               replay: nil,
               recovery: nil
             },
             %RunDetail.RecoveryPolicy{
               step: "send_receipt",
               compensation_callback: nil,
               compensation_status: nil,
               irreversible?: false,
               compensatable?: false,
               replay: :manual_review_required,
               recovery: :manual_intervention
             }
           ]

    refute inspect(detail.recovery_policies) =~ "tok_secret"
    refute inspect(detail.recovery_policies) =~ "ch_sensitive"
    refute inspect(detail.recovery_policies) =~ "receipt-secret"
  end

  test "projects dependency mode from the workflow definition" do
    snapshot =
      snapshot(:running,
        workflow: Atom.to_string(DependencyWorkflow),
        reason: :attempt_visible,
        current_step: "send_email",
        attempts: [attempt("send_email", :claimed, 1, nil)]
      )

    graph =
      graph_inspection(:running,
        workflow: Atom.to_string(DependencyWorkflow),
        current_node_id: "send_email",
        nodes: [
          graph_node("load_account", :completed, false),
          graph_node("load_invoice", :completed, false),
          graph_node("send_email", :running, true)
        ],
        edges: [
          graph_edge("load_account", "load_invoice", :ready),
          graph_edge("load_account", "send_email", :ready),
          graph_edge("load_invoice", "send_email", :ready)
        ]
      )

    explanation =
      diagnostic(
        :running,
        workflow: Atom.to_string(DependencyWorkflow),
        reason: :attempt_visible,
        step: "send_email",
        summary: "A dispatch attempt is visible and waiting for a worker claim.",
        details: %{visible_attempt_count: 1, runnable_keys: ["send_email"]},
        next_actions: [:wait_for_worker_claim],
        evidence: %{attempt_counts: %{claimed: 1}}
      )

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:ok, explanation})

    assert {:ok, %RunDetail{} = detail} = Runs.get_run("run-dependency", client: @client)

    assert detail.workflow_graph.mode == :dependency

    assert Enum.map(detail.workflow_graph.edges, &{&1.from, &1.to, &1.outcome}) == [
             {"load_account", "load_invoice", :ready},
             {"load_account", "send_email", :ready},
             {"load_invoice", "send_email", :ready}
           ]
  end

  test "renders history graphs when the workflow definition is unavailable" do
    snapshot =
      snapshot(:completed,
        workflow: Atom.to_string(MissingWorkflow),
        reason: :terminal,
        current_step: "capture_payment",
        attempts: [
          attempt("load_order", :completed, 1, nil),
          attempt("capture_payment", :completed, 1, nil)
        ]
      )

    graph =
      graph_inspection(:completed,
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

    assert {:ok, %RunDetail{} = detail} = Runs.get_run("run-history", client: @client)

    assert detail.workflow_graph.mode == :history

    assert Enum.map(detail.workflow_graph.nodes, & &1.name) == [
             "load_order",
             "capture_payment"
           ]
  end

  test "returns inspect errors before explaining the run" do
    FakeJizokuClient.put_inspect_run({:error, :invalid_run_id})

    assert {:error, :invalid_run_id} = Runs.get_run("bad", client: @client)
  end

  test "returns explanation errors unchanged" do
    snapshot = snapshot(:running, workflow: Atom.to_string(CheckoutWorkflow))
    graph = graph_inspection(:running, workflow: Atom.to_string(CheckoutWorkflow))

    FakeJizokuClient.put_inspect_run({:ok, snapshot})
    FakeJizokuClient.put_inspect_run_graph({:ok, graph})
    FakeJizokuClient.put_explain_run({:error, :not_found})

    assert {:error, :not_found} = Runs.get_run("run-3", client: @client)
  end

  test "cancels a running workflow" do
    snapshot =
      snapshot(:cancelled, workflow: Atom.to_string(CheckoutWorkflow), reason: :cancelled)

    FakeJizokuClient.put_cancel({:ok, snapshot})

    assert {:ok, updated_snapshot} = Runs.cancel_run("run-1", client: @client)
    assert updated_snapshot.run_id == "run-cancelled"
    assert updated_snapshot.status == :cancelled
  end

  test "returns cancel errors unchanged" do
    FakeJizokuClient.put_cancel({:error, :invalid_run_id})

    assert {:error, :invalid_run_id} = Runs.cancel_run("bad", client: @client)
  end

  test "resumes a paused workflow" do
    snapshot =
      snapshot(:running, workflow: Atom.to_string(CheckoutWorkflow), reason: :attempt_visible)

    FakeJizokuClient.put_resume({:ok, snapshot})

    assert {:ok, updated_snapshot} = Runs.resume_run("run-1", %{}, client: @client)
    assert updated_snapshot.run_id == "run-running"
    assert updated_snapshot.status == :running
  end

  test "returns resume errors unchanged" do
    FakeJizokuClient.put_resume({:error, :not_found})

    assert {:error, :not_found} = Runs.resume_run("missing", %{}, client: @client)
  end

  test "approves a paused approval step" do
    snapshot =
      snapshot(:running, workflow: Atom.to_string(CheckoutWorkflow), reason: :attempt_visible)

    FakeJizokuClient.put_approve({:ok, snapshot})

    assert {:ok, updated_snapshot} =
             Runs.approve_run("run-1", %{"approved_by" => "admin"}, client: @client)

    assert updated_snapshot.run_id == "run-running"
    assert updated_snapshot.status == :running
  end

  test "returns approve errors unchanged" do
    FakeJizokuClient.put_approve({:error, :not_found})

    assert {:error, :not_found} = Runs.approve_run("missing", %{}, client: @client)
  end

  test "rejects a paused approval step" do
    snapshot = snapshot(:failed, workflow: Atom.to_string(CheckoutWorkflow), reason: :terminal)

    FakeJizokuClient.put_reject({:ok, snapshot})

    assert {:ok, updated_snapshot} =
             Runs.reject_run("run-1", %{"rejected_by" => "admin"}, client: @client)

    assert updated_snapshot.run_id == "run-failed"
    assert updated_snapshot.status == :failed
  end

  test "returns reject errors unchanged" do
    FakeJizokuClient.put_reject({:error, :not_found})

    assert {:error, :not_found} = Runs.reject_run("missing", %{}, client: @client)
  end

  test "replays a completed workflow" do
    snapshot =
      snapshot(:running, workflow: Atom.to_string(CheckoutWorkflow), reason: :attempt_visible)

    FakeJizokuClient.put_replay({:ok, snapshot})

    assert {:ok, updated_snapshot} = Runs.replay_run("run-1", client: @client)
    assert updated_snapshot.run_id == "run-running"
    assert updated_snapshot.status == :running
  end

  test "returns replay errors unchanged" do
    FakeJizokuClient.put_replay({:error, {:unsafe_replay, :irreversible_step}})

    assert {:error, {:unsafe_replay, :irreversible_step}} =
             Runs.replay_run("run-1", client: @client)
  end

  defp summary(status, attrs) do
    workflow = Keyword.fetch!(attrs, :workflow)

    %Summary{
      run_id: "run-#{status}",
      workflow: workflow,
      queue: Keyword.get(attrs, :queue, "default"),
      status: status,
      terminal?: status in [:completed, :failed, :cancelled],
      terminal_status: Keyword.get(attrs, :terminal_status, status),
      indexed_at: @now,
      thread_revision: Keyword.get(attrs, :thread_revision, 7),
      anomalies: Keyword.get(attrs, :anomalies, []),
      deadline: Keyword.get(attrs, :deadline),
      definition_version: Keyword.get(attrs, :definition_version, 1)
    }
  end

  defp runtime_spec do
    %{
      workflow: RuntimeCheckout,
      triggers: [%{name: :manual, type: :manual, config: %{}, payload: []}],
      payload: [%{name: :order_id, type: :string, opts: []}],
      steps: [
        %{name: :load_order, action: "load_order", module: :log, opts: [message: "load order"]}
      ],
      transitions: [%{from: :load_order, on: :ok, to: :complete}],
      retries: [],
      entry_steps: [:load_order],
      initial_step: :load_order,
      entry_step: :load_order
    }
  end
end
