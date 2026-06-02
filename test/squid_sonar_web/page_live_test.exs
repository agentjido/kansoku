defmodule SquidSonarWeb.PageLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket
  alias SquidMesh.ReadModel.Listing.Summary
  alias SquidSonar.FakeSquidMeshClient
  alias SquidSonarWeb.PageLive

  setup do
    previous_client = Application.get_env(:squid_sonar, :squid_mesh_client)
    Application.put_env(:squid_sonar, :squid_mesh_client, FakeSquidMeshClient)

    on_exit(fn ->
      if previous_client do
        Application.put_env(:squid_sonar, :squid_mesh_client, previous_client)
      else
        Application.delete_env(:squid_sonar, :squid_mesh_client)
      end
    end)
  end

  test "renders run status counts and recent workflow runs" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:completed, "completed_checkout", "default"),
         summary(:failed, "failing_checkout", "error-queue"),
         summary(:retrying, "retrying_checkout", "retry-queue"),
         summary(:paused, "manual_review_checkout", "approval-queue")
       ]}
    )

    html = render_page()

    assert html =~ "SquidSonar"
    assert html =~ "Runtime dashboard"
    assert html =~ "phx-hook=\"SquidSonarTheme\""
    assert html =~ "Workflow runs"
    assert html =~ "squid-sonar-filter-toggle"
    assert html =~ "Filters"
    refute html =~ "squid-sonar-overview"
    refute html =~ "Status distribution"
    assert html =~ "Search"
    assert html =~ "Page size"
    assert html =~ "Refresh runs"
    assert html =~ "Failed"
    assert html =~ "Completed"
    assert html =~ "Retrying"
    assert html =~ "Paused"
    assert html =~ "Running"
    assert html =~ "Recent runs"
    assert html =~ "completed_checkout"
    assert html =~ "failing_checkout"
    assert html =~ "retry-queue"
    assert html =~ "approval-queue"
  end

  test "renders an empty state when no runs are available" do
    FakeSquidMeshClient.put_list_runs({:ok, []})

    html = render_page()

    assert html =~ "No runs found"
  end

  test "renders a boundary error when runs cannot be loaded" do
    FakeSquidMeshClient.put_list_runs({:error, {:missing_config, [:repo]}})

    html = render_page()

    assert html =~ "Unable to load runs"
    refute html =~ "missing_config"
  end

  test "filters run sections through the LiveView boundary" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:completed, "completed_checkout", "default"),
         summary(:failed, "failing_checkout", "error-queue")
       ]}
    )

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    {:noreply, socket} =
      PageLive.handle_event("filter", %{"filters" => %{"status" => "failed"}}, socket)

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "failing_checkout"
    refute html =~ "completed_checkout"
  end

  test "renders and filters deadline states" do
    FakeSquidMeshClient.put_list_runs(
      {:ok,
       [
         summary(:running, "due_soon_checkout", "default",
           deadline: %{status: :due_soon, step: "capture_payment"}
         ),
         summary(:running, "escalated_checkout", "ops",
           deadline: %{status: :escalated, step: "manual_review"}
         )
       ]}
    )

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "Deadline"
    assert html =~ "due soon"
    assert html =~ "escalated"
    assert html =~ "capture_payment"

    {:noreply, socket} =
      PageLive.handle_event("filter", %{"filters" => %{"deadline" => "escalated"}}, socket)

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "escalated_checkout"
    refute html =~ "due_soon_checkout"
  end

  test "paginates runs through the dashboard boundary" do
    runs =
      for index <- 1..12 do
        summary(:failed, "run-#{index}", "error-queue",
          indexed_at: DateTime.add(~U[2026-05-15 10:00:00Z], index, :second)
        )
      end

    FakeSquidMeshClient.put_list_runs({:ok, runs})

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})
    {:noreply, socket} = PageLive.handle_event("paginate", %{"page" => "2"}, socket)

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "2 / 2"
    assert html =~ "run-2"
    refute html =~ "run-12"
  end

  test "sets dashboard theme without reloading run data" do
    FakeSquidMeshClient.put_list_runs(
      {:ok, [summary(:failed, "failing_checkout", "error-queue")]}
    )

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})
    {:noreply, socket} = PageLive.handle_event("set_theme", %{"theme" => "dark"}, socket)

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "squid-sonar-theme-dark"
    assert html =~ "failing_checkout"
  end

  test "refreshes the dashboard while preserving active filters" do
    FakeSquidMeshClient.put_list_runs(fn filters, _opts ->
      send(self(), {:list_filters, filters})

      {:ok,
       [
         summary(:completed, "completed_checkout", "default"),
         summary(:failed, "failing_checkout", "error-queue")
       ]}
    end)

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    {:noreply, socket} =
      PageLive.handle_event("filter", %{"filters" => %{"status" => "failed"}}, socket)

    FakeSquidMeshClient.put_list_runs(fn filters, _opts ->
      send(self(), {:list_filters, filters})
      {:ok, [summary(:failed, "new_failure_checkout", "error-queue")]}
    end)

    {:noreply, socket} = PageLive.handle_info(:refresh_dashboard, socket)

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "new_failure_checkout"
    refute html =~ "completed_checkout"
    assert socket.assigns.dashboard.filters.status == :failed
  end

  defp render_page do
    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    socket.assigns
    |> PageLive.render()
    |> rendered_to_string()
  end

  defp summary(status, workflow_name, queue, attrs \\ []) do
    %Summary{
      run_id: "#{workflow_name}-run",
      workflow: workflow_name,
      queue: queue,
      status: status,
      terminal?: Keyword.get(attrs, :terminal?, status in [:completed, :failed, :cancelled]),
      terminal_status: Keyword.get(attrs, :terminal_status, status),
      indexed_at: Keyword.get(attrs, :indexed_at, ~U[2026-05-15 10:00:00Z]),
      thread_revision: Keyword.get(attrs, :thread_revision, 7),
      anomalies: [],
      deadline: Keyword.get(attrs, :deadline),
      definition_version: Keyword.get(attrs, :definition_version, 1)
    }
  end
end
