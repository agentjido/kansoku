defmodule SquidSonar.Runs.RunDetailTest do
  use ExUnit.Case, async: true

  import SquidSonar.ReadModelFixtures

  alias SquidSonar.Runs.RunDetail

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

    graph = %{
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

    detail = RunDetail.from_models(snapshot, explanation, graph)

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

    assert detail.dynamic_work == graph.dynamic_work
    assert detail.graph_inspection.dynamic_work_overlays == graph.dynamic_work_overlays
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

    graph = %{
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

    detail = RunDetail.from_models(snapshot, explanation, graph)

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
end
