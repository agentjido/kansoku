defmodule SquidSonar.Runs.RunDetailTest do
  use ExUnit.Case, async: true

  import SquidSonar.ReadModelFixtures

  alias SquidSonar.Runs.RunDetail

  test "projects compensation evidence from policy and compensation attempts" do
    recovery = compensation_recovery("ReleaseInventory", status: :available)

    snapshot =
      snapshot(:failed,
        run_id: "run-compensation-detail",
        workflow: "Elixir.Example.SagaCheckout",
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
        run_id: "run-compensation-detail",
        workflow: "Elixir.Example.SagaCheckout",
        reason: :terminal,
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

    graph =
      graph_inspection(:failed,
        run_id: "run-compensation-detail",
        workflow: "Elixir.Example.SagaCheckout",
        nodes: [
          graph_node("reserve_inventory", :completed, false, recovery: recovery),
          graph_node("fail_payment", :failed, true),
          graph_node("compensate:reserve_inventory", :failed, false)
        ]
      )

    detail = RunDetail.from_models(snapshot, explanation, graph)

    assert [
             %RunDetail.CompensationEvidence{
               step: "fail_payment",
               status: :non_compensatable,
               irreversible?: true,
               compensatable?: false,
               recovery: :manual_intervention
             },
             %RunDetail.CompensationEvidence{
               step: "reserve_inventory",
               compensation_callback: "ReleaseInventory",
               policy_status: :available,
               status: :failed,
               compensation_step: "compensate:reserve_inventory",
               failure_reason: "present"
             }
           ] = detail.compensation_evidence
  end

  test "folds pending compensation runnable sources into the origin step" do
    recovery = compensation_recovery("ReleaseInventory")

    snapshot =
      snapshot(:running,
        run_id: "run-compensation-pending",
        workflow: "Elixir.Example.SagaCheckout",
        reason: :attempt_scheduled_for_later,
        pending_dispatches: [
          %{
            step: "compensate:reserve_inventory",
            recovery: %{
              "irreversible?" => false,
              "compensatable?" => false,
              "replay" => "manual_review_required",
              "recovery" => "manual_intervention"
            }
          }
        ],
        scheduled_attempts: [
          attempt("compensate:reserve_inventory", :retry_scheduled, 1, nil)
        ],
        attempts: [
          attempt("reserve_inventory", :completed, 1, nil, recovery: recovery)
        ]
      )

    explanation =
      diagnostic(:running,
        run_id: "run-compensation-pending",
        workflow: "Elixir.Example.SagaCheckout",
        reason: :attempt_scheduled_for_later,
        evidence:
          recovery_policy_evidence(%{
            "compensate:reserve_inventory" => %{
              "irreversible?" => false,
              "compensatable?" => false,
              "replay" => "manual_review_required",
              "recovery" => "manual_intervention"
            },
            reserve_inventory: recovery
          })
      )

    graph =
      graph_inspection(:running,
        run_id: "run-compensation-pending",
        workflow: "Elixir.Example.SagaCheckout",
        nodes: [
          graph_node("reserve_inventory", :completed, false, recovery: recovery),
          graph_node("compensate:reserve_inventory", :retrying, true)
        ]
      )

    detail = RunDetail.from_models(snapshot, explanation, graph)

    assert [
             %RunDetail.CompensationEvidence{
               step: "reserve_inventory",
               compensation_callback: "ReleaseInventory",
               policy_status: :available,
               status: :scheduled,
               compensation_step: "compensate:reserve_inventory",
               replay: "manual_review_required",
               recovery: "manual_intervention"
             }
           ] = detail.compensation_evidence
  end

  test "projects dynamic work overlays from graph inspection data" do
    recorded_at = ~U[2026-05-15 10:17:00Z]

    snapshot =
      snapshot(:running,
        run_id: "run-dynamic-detail",
        workflow: "Elixir.Example.Checkout",
        reason: :attempt_visible,
        current_step: "capture_payment"
      )

    explanation =
      diagnostic(:running,
        run_id: "run-dynamic-detail",
        workflow: "Elixir.Example.Checkout",
        reason: :attempt_visible,
        step: "capture_payment"
      )

    graph =
      graph_inspection(:running,
        run_id: "run-dynamic-detail",
        workflow: "Elixir.Example.Checkout",
        current_node_id: "capture_payment"
      )

    graph_inspection = %{
      graph
      | dynamic_work: [
          %{
            dynamic_key: "fraud_review",
            nodes: [%{id: "fraud_review"}],
            edges: [%{id: "capture_payment:dynamic:fraud_review"}]
          }
        ],
        dynamic_work_overlays: [
          %{
            dynamic_key: "fraud_review",
            status: :recorded,
            reason: :risk_signal,
            origin: %{step: "capture_payment", branch: "fraud_review"},
            origin_node_id: "capture_payment",
            added_node_ids: ["fraud_review"],
            added_edge_ids: ["capture_payment:dynamic:fraud_review"],
            node_count: 1,
            edge_count: 1,
            recorded_at: recorded_at
          }
        ]
    }

    detail = RunDetail.from_models(snapshot, explanation, graph_inspection)

    assert [
             %RunDetail.DynamicWorkOverlay{
               dynamic_key: "fraud_review",
               status: :recorded,
               reason: :risk_signal,
               origin: %{step: "capture_payment", branch: "fraud_review"},
               origin_node_id: "capture_payment",
               added_node_ids: ["fraud_review"],
               added_edge_ids: ["capture_payment:dynamic:fraud_review"],
               node_count: 1,
               edge_count: 1,
               recorded_at: ^recorded_at
             }
           ] = detail.dynamic_work_overlays

    assert detail.dynamic_work == graph_inspection.dynamic_work
    assert detail.graph_inspection.dynamic_work_overlays == graph_inspection.dynamic_work_overlays

    assert %{
             type: :dynamic_work_recorded,
             occurred_at: ^recorded_at,
             step_id: "capture_payment"
           } = Enum.find(detail.timeline.events, &(&1.type == :dynamic_work_recorded))
  end

  test "normalizes overlay values and filters empty overlay records" do
    snapshot =
      snapshot(:running,
        run_id: "run-dynamic-normalized",
        workflow: "Elixir.Example.Checkout",
        reason: :attempt_visible
      )

    explanation =
      diagnostic(:running,
        run_id: "run-dynamic-normalized",
        workflow: "Elixir.Example.Checkout"
      )

    graph =
      graph_inspection(:running,
        run_id: "run-dynamic-normalized",
        workflow: "Elixir.Example.Checkout"
      )

    graph_inspection = %{
      graph
      | dynamic_work_overlays: [
          %{
            "dynamic_key" => :fraud_review,
            "status" => "recorded",
            "reason" => :operator_inspection,
            "origin_node_id" => :load_order,
            "added_node_ids" => [:fraud_review, "manual_hold", 42],
            "added_edge_ids" => [
              :load_order_dynamic_fraud_review,
              "manual_hold:dynamic:fraud_review"
            ],
            "node_count" => 2,
            "edge_count" => 2
          },
          %{},
          "stale"
        ]
    }

    detail = RunDetail.from_models(snapshot, explanation, graph_inspection)

    assert [
             %RunDetail.DynamicWorkOverlay{
               dynamic_key: "fraud_review",
               status: "recorded",
               reason: :operator_inspection,
               origin_node_id: "load_order",
               added_node_ids: ["fraud_review", "manual_hold"],
               added_edge_ids: [
                 "load_order_dynamic_fraud_review",
                 "manual_hold:dynamic:fraud_review"
               ],
               node_count: 2,
               edge_count: 2
             }
           ] = detail.dynamic_work_overlays
  end

  test "projects live claim and reclaimable expired claim evidence" do
    active_lease_until = ~U[2026-05-15 10:45:00Z]
    active_heartbeat_at = ~U[2026-05-15 10:40:00Z]
    expired_lease_until = ~U[2026-05-15 10:05:00Z]

    active_claim =
      Map.merge(attempt("capture_payment", :claimed, 1, nil), %{
        runnable_key: "run-claims:capture_payment:1",
        owner_id: "worker-a",
        claim_id: "claim-active",
        last_heartbeat_at: active_heartbeat_at,
        lease_until: active_lease_until
      })

    expired_claim =
      Map.merge(attempt("reserve_inventory", :claimed, 1, nil), %{
        runnable_key: "run-claims:reserve_inventory:1",
        owner_id: "worker-b",
        claim_id: "claim-expired",
        lease_until: expired_lease_until
      })

    snapshot =
      snapshot(:running,
        run_id: "run-claims",
        workflow: "Elixir.Example.Checkout",
        reason: :expired_claim,
        current_step: "reserve_inventory",
        attempts: [active_claim],
        expired_claims: [expired_claim],
        anomalies: [
          %{
            reason: :stale_claim,
            runnable_key: "run-claims:reserve_inventory:1",
            claim_id: "claim-expired",
            claim_token_hash: "secret-hash"
          }
        ]
      )

    explanation =
      diagnostic(:running,
        run_id: "run-claims",
        workflow: "Elixir.Example.Checkout",
        reason: :expired_claim,
        step: "reserve_inventory",
        next_actions: [:recover_expired_claim, :cancel]
      )

    graph =
      graph_inspection(:running,
        run_id: "run-claims",
        workflow: "Elixir.Example.Checkout",
        current_node_id: "reserve_inventory",
        nodes: [
          graph_node("capture_payment", :running, false),
          graph_node("reserve_inventory", :running, true)
        ]
      )

    detail = RunDetail.from_models(snapshot, explanation, graph)

    assert [
             %RunDetail.LiveClaim{
               step: "capture_payment",
               status: :active,
               runnable_key: "run-claims:capture_payment:1",
               owner_id: "worker-a",
               claim_id: "claim-active",
               last_heartbeat_at: ^active_heartbeat_at,
               lease_until: ^active_lease_until,
               anomalies: []
             },
             %RunDetail.LiveClaim{
               step: "reserve_inventory",
               status: :reclaimable,
               runnable_key: "run-claims:reserve_inventory:1",
               owner_id: "worker-b",
               claim_id: "claim-expired",
               lease_until: ^expired_lease_until,
               anomalies: [%{reason: :stale_claim, claim_id: "claim-expired"}]
             }
           ] = detail.live_claims

    assert %{
             type: :claim_heartbeat_observed,
             occurred_at: ^active_heartbeat_at,
             step_id: "capture_payment"
           } = Enum.find(detail.timeline.events, &(&1.type == :claim_heartbeat_observed))

    assert %{
             type: :claim_expired,
             occurred_at: ^expired_lease_until,
             step_id: "reserve_inventory"
           } = Enum.find(detail.timeline.events, &(&1.type == :claim_expired))
  end

  test "projects deferred continuation evidence from scheduled attempts" do
    visible_at = ~U[2026-05-15 10:45:00Z]
    deferred_at = ~U[2026-05-15 10:15:00Z]

    deferred_attempt = %{
      step: "capture_payment",
      status: :retry_scheduled,
      attempt_number: 2,
      runnable_key: "run-deferred:capture_payment:2",
      visible_at: visible_at,
      deferred: %{
        reason: %{
          message: :awaiting_provider,
          target: %{step: :capture_payment, branch: :provider_callback},
          context: %{decision: :hold, provider_reference: "pi_123"}
        },
        deferred_at: deferred_at,
        from_runnable_key: "run-deferred:capture_payment:1",
        wakeup: %{visible_at: visible_at}
      }
    }

    snapshot =
      snapshot(:running,
        run_id: "run-deferred",
        workflow: "Elixir.Example.Checkout",
        reason: :deferred_continuation,
        current_step: "capture_payment",
        scheduled_attempts: [deferred_attempt],
        next_visible_at: visible_at
      )

    explanation =
      diagnostic(:running,
        run_id: "run-deferred",
        workflow: "Elixir.Example.Checkout",
        reason: :deferred_continuation,
        step: "capture_payment",
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

    graph =
      graph_inspection(:running,
        run_id: "run-deferred",
        workflow: "Elixir.Example.Checkout",
        current_node_id: "capture_payment",
        nodes: [
          graph_node("capture_payment", :deferred, true)
        ]
      )

    detail = RunDetail.from_models(snapshot, explanation, graph)

    assert [
             %{
               step: "capture_payment",
               status: :deferred,
               runnable_key: "run-deferred:capture_payment:2",
               reason: :awaiting_provider,
               target_step: "capture_payment",
               target_branch: "provider_callback",
               decision_context: %{decision: :hold, provider_reference: "pi_123"},
               visible_at: ^visible_at,
               next_visible_at: ^visible_at,
               deferred_at: ^deferred_at,
               from_runnable_key: "run-deferred:capture_payment:1",
               wakeup: %{visible_at: ^visible_at}
             }
           ] = Map.get(detail, :deferred_continuations)

    assert %{
             type: :continuation_deferred,
             occurred_at: ^deferred_at,
             step_id: "capture_payment"
           } = Enum.find(detail.timeline.events, &(&1.type == :continuation_deferred))

    assert [
             %{
               reason: :awaiting_provider,
               target_step: "capture_payment",
               target_branch: "provider_callback"
             }
           ] = detail.graph_inspection.deferred_continuations
  end

  test "adds reached deadline states to the chronological timeline" do
    due_soon_at = ~U[2026-05-15 10:10:00Z]
    due_at = ~U[2026-05-15 10:15:00Z]
    escalated_at = ~U[2026-05-15 10:20:00Z]

    deadline = %{
      status: :escalated,
      step: "capture_payment",
      due_soon_at: due_soon_at,
      due_at: due_at,
      escalated_at: escalated_at
    }

    snapshot =
      snapshot(:running,
        run_id: "run-deadline-timeline",
        workflow: "Elixir.Example.Checkout",
        current_step: "capture_payment",
        deadline: deadline
      )

    explanation =
      diagnostic(:running,
        run_id: "run-deadline-timeline",
        workflow: "Elixir.Example.Checkout",
        step: "capture_payment"
      )

    graph =
      graph_inspection(:running,
        run_id: "run-deadline-timeline",
        workflow: "Elixir.Example.Checkout",
        current_node_id: "capture_payment"
      )

    detail = RunDetail.from_models(snapshot, explanation, graph)

    assert [
             %{type: :deadline_due_soon, occurred_at: ^due_soon_at},
             %{type: :deadline_overdue, occurred_at: ^due_at},
             %{type: :deadline_escalated, occurred_at: ^escalated_at}
           ] =
             Enum.filter(
               detail.timeline.events,
               &String.starts_with?(to_string(&1.type), "deadline_")
             )
  end
end
