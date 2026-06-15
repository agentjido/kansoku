defmodule SquidSonarWeb.PageLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveViewTest
  import SquidSonar.ReadModelFixtures

  alias Phoenix.LiveView.Socket
  alias Squidie.ReadModel.Listing.Summary
  alias SquidSonar.FakeSquidieClient
  alias SquidSonarWeb.PageLive

  defmodule CatalogWorkflow do
    use Squidie.Workflow

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

  test "renders run status counts and recent workflow runs" do
    FakeSquidieClient.put_list_runs(
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
    FakeSquidieClient.put_list_runs({:ok, []})

    html = render_page()

    assert html =~ "No runs found"
  end

  test "renders a boundary error when runs cannot be loaded" do
    FakeSquidieClient.put_list_runs({:error, {:missing_config, [:repo]}})

    html = render_page()

    assert html =~ "Unable to load runs"
    refute html =~ "missing_config"
  end

  test "filters run sections through the LiveView boundary" do
    FakeSquidieClient.put_list_runs(
      {:ok,
       [
         summary(:completed, "completed_checkout", "default"),
         summary(:failed, "failing_checkout", "error-queue")
       ]}
    )

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    {:noreply, filtered_socket} =
      PageLive.handle_event("filter", %{"filters" => %{"status" => "failed"}}, socket)

    html =
      filtered_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "failing_checkout"
    refute html =~ "completed_checkout"
  end

  test "renders and filters deadline states" do
    FakeSquidieClient.put_list_runs(
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

    initial_html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert initial_html =~ "Deadline"
    assert initial_html =~ "due soon"
    assert initial_html =~ "escalated"
    assert initial_html =~ "capture_payment"

    {:noreply, filtered_socket} =
      PageLive.handle_event("filter", %{"filters" => %{"deadline" => "escalated"}}, socket)

    filtered_html =
      filtered_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert filtered_html =~ "escalated_checkout"
    refute filtered_html =~ "due_soon_checkout"
  end

  test "paginates runs through the dashboard boundary" do
    runs =
      for index <- 1..12 do
        summary(:failed, "run-#{index}", "error-queue",
          indexed_at: DateTime.add(~U[2026-05-15 10:00:00Z], index, :second)
        )
      end

    FakeSquidieClient.put_list_runs({:ok, runs})

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})
    {:noreply, paginated_socket} = PageLive.handle_event("paginate", %{"page" => "2"}, socket)

    html =
      paginated_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "2 / 2"
    assert html =~ "run-2"
    refute html =~ "run-12"
  end

  test "sets dashboard theme without reloading run data" do
    FakeSquidieClient.put_list_runs({:ok, [summary(:failed, "failing_checkout", "error-queue")]})

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})
    {:noreply, themed_socket} = PageLive.handle_event("set_theme", %{"theme" => "dark"}, socket)

    html =
      themed_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "squid-sonar-theme-dark"
    assert html =~ "failing_checkout"
  end

  test "opens and closes the runtime spec drawer from the dashboard" do
    FakeSquidieClient.put_list_runs({:ok, []})

    {:ok, socket} = mount_with_runtime_spec()

    initial_html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert initial_html =~ "Start workflow"
    refute initial_html =~ "squid-sonar-runtime-spec-drawer"
    refute initial_html =~ "/runtime-specs/new"

    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    open_html =
      open_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert open_html =~ "squid-sonar-runtime-spec-drawer"
    assert open_html =~ "name=\"runtime_spec_start[workflow]\""
    assert open_html =~ "RuntimeCheckout"
    assert open_html =~ "Payload JSON"
    assert open_html =~ "The host application provides the workflow catalog"
    assert open_html =~ "order_id"
    assert open_html =~ "order_id_example"
    refute open_html =~ "Example payload"
    assert open_html =~ "Host-approved workflow"
    assert open_html =~ "Close workflow starter"

    {:noreply, closed_socket} =
      PageLive.handle_event("close_runtime_spec_drawer", %{}, open_socket)

    closed_html =
      closed_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    refute closed_html =~ "squid-sonar-runtime-spec-drawer"
  end

  test "derives the workflow dropdown and example payload from the host runtime spec" do
    FakeSquidieClient.put_list_runs({:ok, []})

    spec = %{
      runtime_spec()
      | workflow: InvoiceReconciliation,
        payload: [
          %{name: :invoice_id, type: :string, opts: []},
          %{name: :retry_count, type: :integer, opts: []}
        ]
    }

    {:ok, socket} = mount_with_runtime_spec(spec)
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    html =
      open_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "InvoiceReconciliation"
    assert html =~ "invoice_id"
    assert html =~ "invoice_id_example"
    assert html =~ "retry_count"
    assert html =~ "1"
    refute html =~ "RuntimeCheckout"
  end

  test "converts host-configured DSL workflow modules into catalog specs" do
    FakeSquidieClient.put_list_runs({:ok, []})

    {:ok, socket} = mount_with_runtime_specs(account_setup: CatalogWorkflow)
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    html =
      open_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "CatalogWorkflow"
    assert html =~ "account_id"
    assert html =~ "account_id_example"
  end

  test "selects a host-configured workflow catalog entry and updates payload JSON" do
    FakeSquidieClient.put_list_runs({:ok, []})

    invoice_spec = invoice_runtime_spec()

    {:ok, socket} =
      mount_with_runtime_specs(
        checkout: runtime_spec(),
        invoice_reconciliation: invoice_spec
      )

    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    open_html =
      open_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert open_html =~ "RuntimeCheckout"
    assert open_html =~ "InvoiceReconciliation"
    assert open_html =~ "order_id_example"

    {:noreply, selected_socket} =
      PageLive.handle_event(
        "select_runtime_spec",
        %{"runtime_spec_start" => %{"workflow" => "invoice_reconciliation"}},
        open_socket
      )

    selected_html =
      selected_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert selected_html =~ "invoice_id_example"
    assert selected_html =~ "retry_count"
    refute selected_html =~ "order_id_example"
  end

  test "preserves edited payload JSON when the selected workflow does not change" do
    FakeSquidieClient.put_list_runs({:ok, []})

    {:ok, socket} = mount_with_runtime_specs(checkout: runtime_spec())
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, changed_socket} =
      PageLive.handle_event(
        "select_runtime_spec",
        %{
          "runtime_spec_start" => %{
            "workflow" => "checkout",
            "payload_json" => ~s({"order_id":"typed-order"})
          }
        },
        open_socket
      )

    html =
      changed_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "typed-order"
    refute html =~ "order_id_example"
  end

  test "starts the selected workflow catalog entry" do
    FakeSquidieClient.put_list_runs({:ok, []})

    checkout_spec = runtime_spec()
    invoice_spec = invoice_runtime_spec()
    registry = %{"load_order" => __MODULE__}
    payload = %{"invoice_id" => "inv-1", "retry_count" => 2}
    normalized_payload = %{invoice_id: "inv-1", retry_count: 2}

    FakeSquidieClient.put_start_spec(fn started_spec, started_payload, opts ->
      send(self(), {:start_spec, started_spec, started_payload, opts})

      {:ok,
       snapshot(:running,
         run_id: "invoice-runtime-spec-run",
         workflow: "InvoiceReconciliation",
         reason: :attempt_visible
       )}
    end)

    {:ok, socket} =
      mount_with_runtime_specs(
        [checkout: checkout_spec, invoice_reconciliation: invoice_spec],
        registry
      )

    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, started_socket} =
      PageLive.handle_event(
        "start_runtime_spec",
        %{
          "runtime_spec_start" => %{
            "workflow" => "invoice_reconciliation",
            "payload_json" => Jason.encode!(payload)
          }
        },
        open_socket
      )

    assert_received {:start_spec, ^invoice_spec, ^normalized_payload,
                     [action_registry: ^registry]}

    assert {:live, :redirect, %{to: "/sonar/runs/invoice-runtime-spec-run"}} =
             started_socket.redirected
  end

  test "starts DSL workflow catalog entries through the workflow start boundary" do
    FakeSquidieClient.put_list_runs({:ok, []})

    FakeSquidieClient.put_start(fn workflow, payload, opts ->
      send(self(), {:start_workflow, workflow, payload, opts})

      {:ok,
       snapshot(:running,
         run_id: "catalog-workflow-run",
         workflow: Atom.to_string(workflow),
         reason: :attempt_visible
       )}
    end)

    FakeSquidieClient.put_start_spec(fn _spec, _payload, _opts ->
      send(self(), :unexpected_start_spec)
      {:error, :unexpected_start_spec}
    end)

    {:ok, socket} = mount_with_runtime_specs(account_setup: CatalogWorkflow)
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, started_socket} =
      PageLive.handle_event(
        "start_runtime_spec",
        %{
          "runtime_spec_start" => %{
            "workflow" => "account_setup",
            "payload_json" => Jason.encode!(%{"account_id" => "acct-1"})
          }
        },
        open_socket
      )

    assert_received {:start_workflow, CatalogWorkflow, %{account_id: "acct-1"}, []}
    refute_received :unexpected_start_spec

    assert {:live, :redirect, %{to: "/sonar/runs/catalog-workflow-run"}} =
             started_socket.redirected
  end

  test "rejects stale runtime spec workflow keys from the client" do
    FakeSquidieClient.put_list_runs({:ok, []})

    FakeSquidieClient.put_start_spec(fn _spec, _payload, _opts ->
      send(self(), :unexpected_start_spec)
      {:error, :unexpected}
    end)

    {:ok, socket} = mount_with_runtime_specs(checkout: runtime_spec())
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, error_socket} =
      PageLive.handle_event(
        "start_runtime_spec",
        %{
          "runtime_spec_start" => %{
            "workflow" => "not_configured",
            "payload_json" => Jason.encode!(%{"order_id" => "order-1"})
          }
        },
        open_socket
      )

    html =
      error_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "Selected workflow is not configured"
    refute_received :unexpected_start_spec
  end

  test "starts a runtime spec from the drawer and redirects to the created run detail" do
    FakeSquidieClient.put_list_runs({:ok, []})

    spec = runtime_spec()
    registry = %{"load_order" => __MODULE__}
    payload = %{"order_id" => "order-1"}
    normalized_payload = %{order_id: "order-1"}

    FakeSquidieClient.put_start_spec(fn started_spec, started_payload, opts ->
      send(self(), {:start_spec, started_spec, started_payload, opts})

      {:ok,
       snapshot(:running,
         run_id: "runtime-spec-run",
         workflow: "RuntimeCheckout",
         reason: :attempt_visible
       )}
    end)

    {:ok, socket} = mount_with_runtime_spec(spec, registry)
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, started_socket} =
      PageLive.handle_event(
        "start_runtime_spec",
        %{"runtime_spec_start" => %{"payload_json" => Jason.encode!(payload)}},
        open_socket
      )

    assert_received {:start_spec, ^spec, ^normalized_payload, [action_registry: ^registry]}
    assert {:live, :redirect, %{to: "/sonar/runs/runtime-spec-run"}} = started_socket.redirected
  end

  test "renders invalid runtime spec payload JSON in the drawer without echoing raw input" do
    FakeSquidieClient.put_list_runs({:ok, []})

    {:ok, socket} = mount_with_runtime_spec()
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, error_socket} =
      PageLive.handle_event(
        "start_runtime_spec",
        %{"runtime_spec_start" => %{"payload_json" => "{bad"}},
        open_socket
      )

    html =
      error_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "Payload JSON is invalid"
    refute html =~ "{bad"
  end

  test "renders structured runtime spec validation errors in the drawer" do
    FakeSquidieClient.put_list_runs({:ok, []})

    FakeSquidieClient.put_start_spec(
      {:error,
       {:invalid_workflow_spec,
        [
          %{
            path: [:steps, 0, :action],
            code: :unknown_action_key,
            message: "step load_order references unknown action key",
            details: %{secret: "do-not-render"}
          }
        ]}}
    )

    {:ok, socket} = mount_with_runtime_spec()
    {:noreply, open_socket} = PageLive.handle_event("open_runtime_spec_drawer", %{}, socket)

    {:noreply, error_socket} =
      PageLive.handle_event(
        "start_runtime_spec",
        %{"runtime_spec_start" => %{"payload_json" => "{}"}},
        open_socket
      )

    html =
      error_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "step load_order references unknown action key"
    assert html =~ "steps.0.action"
    refute html =~ "do-not-render"
  end

  test "does not render the runtime spec trigger without host configuration" do
    FakeSquidieClient.put_list_runs({:ok, []})

    html = render_page()

    refute html =~ "Start workflow"
    refute html =~ "squid-sonar-runtime-spec-drawer"
  end

  test "lists host-provided saved workflow specs on the dashboard" do
    FakeSquidieClient.put_list_runs({:ok, []})

    {:ok, socket} =
      mount_with_saved_specs(
        checkout_runtime_spec: %{
          title: "Checkout runtime spec",
          status: :approved,
          editor_json: editor_json()
        }
      )

    html =
      socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "Saved workflow specs"
    assert html =~ "Checkout runtime spec"
    assert html =~ "Approved"
    assert html =~ ~s(href="/sonar/saved-specs/checkout_runtime_spec")
  end

  test "does not render saved workflow specs without host configuration" do
    FakeSquidieClient.put_list_runs({:ok, []})

    html = render_page()

    refute html =~ "Saved workflow specs"
    refute html =~ "/saved-specs/"
  end

  test "refreshes the dashboard while preserving active filters" do
    FakeSquidieClient.put_list_runs(fn filters, _opts ->
      send(self(), {:list_filters, filters})

      {:ok,
       [
         summary(:completed, "completed_checkout", "default"),
         summary(:failed, "failing_checkout", "error-queue")
       ]}
    end)

    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    {:noreply, filtered_socket} =
      PageLive.handle_event("filter", %{"filters" => %{"status" => "failed"}}, socket)

    FakeSquidieClient.put_list_runs(fn filters, _opts ->
      send(self(), {:list_filters, filters})
      {:ok, [summary(:failed, "new_failure_checkout", "error-queue")]}
    end)

    {:noreply, refreshed_socket} = PageLive.handle_info(:refresh_dashboard, filtered_socket)

    html =
      refreshed_socket.assigns
      |> PageLive.render()
      |> rendered_to_string()

    assert html =~ "new_failure_checkout"
    refute html =~ "completed_checkout"
    assert refreshed_socket.assigns.dashboard.filters.status == :failed
  end

  defp render_page do
    {:ok, socket} = PageLive.mount(%{}, %{}, %Socket{})

    socket.assigns
    |> PageLive.render()
    |> rendered_to_string()
  end

  defp mount_with_runtime_spec(spec \\ runtime_spec(), registry \\ %{"load_order" => __MODULE__}) do
    socket =
      %Socket{}
      |> assign(:prefix, "/sonar")
      |> assign(:runtime_spec, spec)
      |> assign(:action_registry, registry)

    PageLive.mount(%{}, %{}, socket)
  end

  defp mount_with_runtime_specs(runtime_specs, registry \\ %{"load_order" => __MODULE__}) do
    socket =
      %Socket{}
      |> assign(:prefix, "/sonar")
      |> assign(:runtime_specs, runtime_specs)
      |> assign(:action_registry, registry)

    PageLive.mount(%{}, %{}, socket)
  end

  defp mount_with_saved_specs(saved_specs, registry \\ nil) do
    socket =
      %Socket{}
      |> assign(:prefix, "/sonar")
      |> assign(:saved_specs, saved_specs)
      |> assign(:action_registry, registry)

    PageLive.mount(%{}, %{}, socket)
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

  defp invoice_runtime_spec do
    %{
      runtime_spec()
      | workflow: InvoiceReconciliation,
        payload: [
          %{name: :invoice_id, type: :string, opts: []},
          %{name: :retry_count, type: :integer, opts: []}
        ]
    }
  end

  defp editor_json do
    %{
      "workflow" => "RuntimeCheckout",
      "triggers" => [%{"name" => "manual", "type" => "manual", "config" => %{}, "payload" => []}],
      "payload" => [%{"name" => "order_id", "type" => "string", "opts" => []}],
      "steps" => [%{"name" => "load_order", "action" => "load_order", "opts" => %{}}],
      "transitions" => [%{"from" => "load_order", "on" => "ok", "to" => "complete"}],
      "retries" => [],
      "entry_steps" => ["load_order"],
      "initial_step" => "load_order",
      "entry_step" => "load_order"
    }
  end
end
