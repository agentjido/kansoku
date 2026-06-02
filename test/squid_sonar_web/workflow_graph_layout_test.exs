defmodule SquidSonarWeb.WorkflowGraphLayoutTest do
  use ExUnit.Case, async: true

  alias SquidSonar.Runs.WorkflowGraph
  alias SquidSonarWeb.WorkflowGraphLayout

  test "uses the computed height for nodes with deadline evidence" do
    layout =
      WorkflowGraphLayout.build(%WorkflowGraph{
        nodes: [
          %WorkflowGraph.Node{
            name: "capture_payment",
            label: "Capture payment",
            status: :running,
            deadline: %{status: :overdue, due_at: ~U[2026-05-15 10:15:00Z]}
          }
        ],
        edges: []
      })

    assert [%{height: 118}] = layout.nodes
    assert layout.height == 158
  end

  test "uses the computed height for nodes with compensation callbacks" do
    layout =
      WorkflowGraphLayout.build(%WorkflowGraph{
        nodes: [
          %WorkflowGraph.Node{
            name: "capture_payment",
            label: "Capture payment",
            status: :failed,
            recovery: %{
              compensation: %{
                callback: SquidSonar.TestSupport.Workflows.ReleaseInventory,
                status: :available
              }
            }
          }
        ],
        edges: []
      })

    assert [%{height: 112}] = layout.nodes
  end

  test "uses enough height for nodes with deadline and compensation evidence" do
    layout =
      WorkflowGraphLayout.build(%WorkflowGraph{
        nodes: [
          %WorkflowGraph.Node{
            name: "capture_payment",
            label: "Capture payment",
            status: :running,
            deadline: %{status: :overdue, due_at: ~U[2026-05-15 10:15:00Z]},
            recovery: %{
              compensation: %{
                callback: SquidSonar.TestSupport.Workflows.ReleaseInventory,
                status: :available
              }
            }
          }
        ],
        edges: []
      })

    assert [%{height: 172}] = layout.nodes
    assert layout.height == 212
  end

  test "uses the standard track height when compensation callback is absent" do
    layout =
      WorkflowGraphLayout.build(%WorkflowGraph{
        nodes: [
          %WorkflowGraph.Node{
            name: "capture_payment",
            label: "Capture payment",
            status: :failed,
            recovery: %{
              compensation: %{
                status: :available
              }
            }
          }
        ],
        edges: []
      })

    assert [%{height: 58}] = layout.nodes
    assert layout.height == 98
  end
end
