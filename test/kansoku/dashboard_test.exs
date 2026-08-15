defmodule Kansoku.DashboardTest do
  use ExUnit.Case, async: true

  import Kansoku.ReadModelFixtures

  alias Jizoku.ReadModel.Listing.Summary
  alias Kansoku.Dashboard
  alias Kansoku.FakeJizokuClient

  @loaded_at ~U[2026-05-15 10:30:00Z]

  test "loads recent runs with status counts" do
    FakeJizokuClient.put_list_runs(
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

    dashboard = Dashboard.load(client: FakeJizokuClient, loaded_at: @loaded_at)

    assert [_first, _second, _third, _fourth, _fifth, _sixth] = dashboard.runs
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
    FakeJizokuClient.put_list_runs(
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
        client: FakeJizokuClient,
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

    FakeJizokuClient.put_list_runs({:ok, runs})

    dashboard =
      Dashboard.load(
        client: FakeJizokuClient,
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
    FakeJizokuClient.put_list_runs(
      {:ok,
       [
         summary(:completed),
         summary(:failed),
         summary(:running, queue: "capture-payment")
       ]}
    )

    dashboard =
      Dashboard.load(
        client: FakeJizokuClient,
        loaded_at: @loaded_at,
        filters: %{"query" => "capture"}
      )

    assert [%{status: :running, queue: "capture-payment"}] = dashboard.runs
  end

  test "filters runs by deadline state" do
    FakeJizokuClient.put_list_runs(
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
        client: FakeJizokuClient,
        loaded_at: @loaded_at,
        filters: %{"deadline" => "escalated"}
      )

    assert dashboard.filters.deadline == :escalated
    assert Enum.map(dashboard.runs, & &1.id) == ["escalated-run"]
    assert dashboard.filtered_count == 1
  end

  test "normalizes and serializes stable shareable filter params" do
    normalized =
      Dashboard.normalize_params(%{
        "workflow" => "  BillingWorkflow  ",
        "status" => "failed",
        "terminal" => "cancelled",
        "queue" => " billing ",
        "window" => "24h",
        "run_id" => "run-prefix",
        "manual" => "waiting",
        "deadline" => "overdue",
        "query" => " invoice ",
        "page" => "2",
        "page_size" => "25",
        "ignored" => "must-not-survive"
      })

    assert normalized.filters == %{
             workflow: "BillingWorkflow",
             status: :failed,
             terminal: :cancelled,
             queue: "billing",
             window: :"24h",
             run_id: "run-prefix",
             manual: :waiting,
             deadline: :overdue,
             query: "invoice"
           }

    assert normalized.page == 2
    assert normalized.page_size == 25

    assert Dashboard.query_params(normalized.filters, normalized.page, normalized.page_size) == [
             {"workflow", "BillingWorkflow"},
             {"status", "failed"},
             {"terminal", "cancelled"},
             {"queue", "billing"},
             {"window", "24h"},
             {"run_id", "run-prefix"},
             {"manual", "waiting"},
             {"deadline", "overdue"},
             {"query", "invoice"},
             {"page", "2"},
             {"page_size", "25"}
           ]
  end

  test "drops unknown, nested, and oversized filter values" do
    oversized = String.duplicate("x", 300)

    normalized =
      Dashboard.normalize_params(%{
        "workflow" => %{"nested" => "value"},
        "status" => "not-a-status",
        "terminal" => ["failed"],
        "queue" => oversized,
        "window" => "yesterday",
        "run_id" => "bad/path",
        "manual" => "sometimes",
        "page" => "-2",
        "page_size" => "500"
      })

    assert normalized.filters.workflow == ""
    assert normalized.filters.status == :all
    assert normalized.filters.terminal == :all
    assert normalized.filters.queue == ""
    assert normalized.filters.window == :all
    assert normalized.filters.run_id == ""
    assert normalized.filters.manual == :all
    assert normalized.page == 1
    assert normalized.page_size == 10
  end

  test "filters by workflow, terminal status, queue, time window, and run id prefix" do
    FakeJizokuClient.put_list_runs(
      {:ok,
       [
         summary(:failed,
           run_id: "billing-recent-1",
           workflow: "BillingWorkflow",
           queue: "billing",
           terminal_status: :failed,
           indexed_at: DateTime.add(@loaded_at, -30, :minute)
         ),
         summary(:failed,
           run_id: "billing-old-1",
           workflow: "BillingWorkflow",
           queue: "billing",
           terminal_status: :failed,
           indexed_at: DateTime.add(@loaded_at, -2, :hour)
         ),
         summary(:failed,
           run_id: "shipping-recent-1",
           workflow: "ShippingWorkflow",
           queue: "shipping",
           terminal_status: :failed,
           indexed_at: DateTime.add(@loaded_at, -10, :minute)
         )
       ]}
    )

    dashboard =
      Dashboard.load(
        client: FakeJizokuClient,
        loaded_at: @loaded_at,
        filters: %{
          "workflow" => "BillingWorkflow",
          "terminal" => "failed",
          "queue" => "billing",
          "window" => "1h",
          "run_id" => "billing-recent"
        }
      )

    assert Enum.map(dashboard.runs, & &1.id) == ["billing-recent-1"]
    assert dashboard.workflows == ["BillingWorkflow", "ShippingWorkflow"]
    assert dashboard.queues == ["billing", "shipping"]
  end

  test "filters manual-action state through visibility-aware queue inspection" do
    all_runs = [
      summary(:paused, run_id: "manual-run", workflow: "ReviewWorkflow"),
      summary(:paused, run_id: "ordinary-paused-run", workflow: "WaitWorkflow"),
      summary(:running, run_id: "running-run")
    ]

    FakeJizokuClient.put_list_runs(fn filters, _opts ->
      if Keyword.get(filters, :status) == :paused do
        {:ok, Enum.filter(all_runs, &(&1.status == :paused))}
      else
        {:ok, all_runs}
      end
    end)

    FakeJizokuClient.put_inspect_run(fn
      "manual-run", _opts ->
        {:ok,
         snapshot(:paused,
           run_id: "manual-run",
           workflow: "ReviewWorkflow",
           terminal?: false,
           manual_state: %{kind: "approval", step: "review"}
         )}

      "ordinary-paused-run", _opts ->
        {:ok,
         snapshot(:paused,
           run_id: "ordinary-paused-run",
           workflow: "WaitWorkflow",
           terminal?: false,
           manual_state: nil
         )}
    end)

    waiting =
      Dashboard.load(
        client: FakeJizokuClient,
        loaded_at: @loaded_at,
        filters: %{"manual" => "waiting"},
        visibility_actor: "operator-1",
        visibility_policy: :operator
      )

    assert Enum.map(waiting.runs, & &1.id) == ["manual-run"]

    none =
      Dashboard.load(
        client: FakeJizokuClient,
        loaded_at: @loaded_at,
        filters: %{"manual" => "none"},
        visibility_actor: "operator-1",
        visibility_policy: :operator
      )

    assert MapSet.new(none.runs, & &1.id) ==
             MapSet.new(["running-run", "ordinary-paused-run"])
  end

  test "preserves stale selected workflow and queue values for shareable controls" do
    FakeJizokuClient.put_list_runs({:ok, []})

    dashboard =
      Dashboard.load(
        client: FakeJizokuClient,
        filters: %{"workflow" => "ArchivedWorkflow", "queue" => "archived"}
      )

    assert dashboard.workflows == ["ArchivedWorkflow"]
    assert dashboard.queues == ["archived"]
    assert dashboard.runs == []
  end

  test "resolves only unique, valid run id prefixes from recent visible summaries" do
    FakeJizokuClient.put_list_runs(
      {:ok,
       [
         summary(:running, run_id: "run-alpha-001"),
         summary(:running, run_id: "run-alpha-002"),
         summary(:completed, run_id: "run-beta-001")
       ]}
    )

    assert {:ok, "run-beta-001"} =
             Dashboard.resolve_run_prefix("run-beta", client: FakeJizokuClient)

    assert {:ok, "run-alpha-001"} =
             Dashboard.resolve_run_prefix("run-alpha-001", client: FakeJizokuClient)

    assert {:error, :ambiguous} =
             Dashboard.resolve_run_prefix("run-alpha", client: FakeJizokuClient)

    assert {:error, :not_found} =
             Dashboard.resolve_run_prefix("run-missing", client: FakeJizokuClient)

    assert {:error, :invalid_prefix} =
             Dashboard.resolve_run_prefix("../runs/secret", client: FakeJizokuClient)
  end

  test "keeps error state at the dashboard boundary" do
    FakeJizokuClient.put_list_runs({:error, {:missing_config, [:repo]}})

    dashboard = Dashboard.load(client: FakeJizokuClient, loaded_at: @loaded_at)

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
