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

    assert [
             %{
               reason: :awaiting_provider,
               target_step: "capture_payment",
               target_branch: "provider_callback"
             }
           ] = detail.graph_inspection.deferred_continuations
  end
end
