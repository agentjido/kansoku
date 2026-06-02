defmodule SquidSonar.DashboardTest do
  use ExUnit.Case, async: true

  alias SquidMesh.ReadModel.Listing.Summary
  alias SquidSonar.Dashboard
  alias SquidSonar.FakeSquidMeshClient

  @loaded_at ~U[2026-05-15 10:30:00Z]

  test "loads recent runs with status counts" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:completed),
         summary(:failed),
         summary(:failed),
         summary(:retrying),
         summary(:paused),
         summary(:running)
       ]}
    )

    dashboard = Dashboard.load(client: FakeSquidMeshClient, loaded_at: @loaded_at)

    assert length(dashboard.runs) == 6
    assert dashboard.loaded_at == @loaded_at
    assert dashboard.load_error == nil
    assert dashboard.status_counts.completed == 1
    assert dashboard.status_counts.failed == 2
    assert dashboard.status_counts.retrying == 1
    assert dashboard.status_counts.paused == 1
    assert dashboard.status_counts.running == 1
    assert dashboard.loaded_count == 6
    assert dashboard.filtered_count == 6
  end

  test "filters runs by status while preserving date order" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:completed, indexed_at: ~U[2026-05-15 10:00:00Z]),
         summary(:failed, run_id: "failed-old", indexed_at: ~U[2026-05-15 10:01:00Z]),
         summary(:failed, run_id: "failed-new", indexed_at: ~U[2026-05-15 10:03:00Z]),
         summary(:running, indexed_at: ~U[2026-05-15 10:02:00Z])
       ]}
    )

    dashboard =
      Dashboard.load(
        client: FakeSquidMeshClient,
        loaded_at: @loaded_at,
        filters: %{"status" => "failed"}
      )

    assert Enum.map(dashboard.runs, & &1.status) == [:failed, :failed]
    assert Enum.map(dashboard.runs, & &1.id) == ["failed-new", "failed-old"]
    assert dashboard.filtered_count == 2
    assert dashboard.loaded_count == 4
    assert dashboard.status_counts.completed == 1
  end

  test "paginates filtered runs" do
    runs =
      for index <- 1..12 do
        summary(:failed,
          run_id: "run-#{index}",
          indexed_at: DateTime.add(@loaded_at, index, :second)
        )
      end

    FakeSquidMeshClient.put_list_runs({:ok, runs})

    dashboard =
      Dashboard.load(
        client: FakeSquidMeshClient,
        loaded_at: @loaded_at,
        filters: %{"status" => "failed"},
        page: "2",
        page_size: "10"
      )

    assert dashboard.page == 2
    assert dashboard.page_size == 10
    assert dashboard.total_pages == 2
    assert dashboard.filtered_count == 12
    assert Enum.map(dashboard.runs, & &1.id) == ["run-2", "run-1"]
  end

  test "filters runs by dashboard search text" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:completed),
         summary(:failed),
         summary(:running, queue: "capture-payment")
       ]}
    )

    dashboard =
      Dashboard.load(
        client: FakeSquidMeshClient,
        loaded_at: @loaded_at,
        filters: %{"query" => "capture"}
      )

    assert [%{status: :running, queue: "capture-payment"}] = dashboard.runs
  end

  test "filters runs by deadline state" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:running,
           run_id: "due-soon-run",
           deadline: %{status: :due_soon, step: "capture_payment"}
         ),
         summary(:running,
           run_id: "escalated-run",
           deadline: %{status: :escalated, step: "manual_review"}
         ),
         summary(:completed, run_id: "completed-run", deadline: nil)
       ]}
    )

    dashboard =
      Dashboard.load(
        client: FakeSquidMeshClient,
        loaded_at: @loaded_at,
        filters: %{"deadline" => "escalated"}
      )

    assert dashboard.filters.deadline == :escalated
    assert Enum.map(dashboard.runs, & &1.id) == ["escalated-run"]
    assert dashboard.filtered_count == 1
  end

  test "keeps error state at the dashboard boundary" do
    FakeSquidMeshClient.put_list_runs({:error, {:missing_config, [:repo]}})

    dashboard = Dashboard.load(client: FakeSquidMeshClient, loaded_at: @loaded_at)

    assert dashboard.runs == []
    assert dashboard.status_counts.failed == 0
    assert dashboard.load_error == {:missing_config, [:repo]}
  end

  defp summary(status, attrs \\ []) do
    %Summary{
      run_id: Keyword.get(attrs, :run_id, "#{status}-run"),
      workflow: Keyword.get(attrs, :workflow, "ExampleWorkflow"),
      queue: Keyword.get(attrs, :queue, "default"),
      status: status,
      terminal?: Keyword.get(attrs, :terminal?, status in [:completed, :failed, :cancelled]),
      terminal_status: Keyword.get(attrs, :terminal_status, status),
      indexed_at: Keyword.get(attrs, :indexed_at, @loaded_at),
      thread_revision: Keyword.get(attrs, :thread_revision, 7),
      anomalies: Keyword.get(attrs, :anomalies, []),
      deadline: Keyword.get(attrs, :deadline),
      definition_version: Keyword.get(attrs, :definition_version, 1)
    }
  end
end
