defmodule KansokuWeb.OperatorQueuesLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Jizoku.ReadModel.Inspection.Snapshot
  alias Jizoku.ReadModel.Listing.Summary
  alias Kansoku.OperatorQueues.ManualAction
  alias Kansoku.OperatorQueues.Schedule
  alias KansokuWeb.OperatorQueuesLive
  alias Phoenix.LiveView.Async
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.LiveStream
  alias Phoenix.LiveView.Socket

  defmodule AsyncClient do
    @behaviour Kansoku.JizokuClient

    @impl Kansoku.JizokuClient
    def list_runs(_filters, _opts) do
      {:ok,
       [
         %Summary{
           run_id: "async-run",
           workflow: "Checkout",
           definition_version: "1",
           queue: "approvals",
           status: :paused,
           terminal?: false,
           terminal_status: nil,
           deadline: nil,
           indexed_at: ~U[2026-07-11 14:45:00Z],
           thread_revision: 1,
           anomalies: []
         }
       ]}
    end

    @impl Kansoku.JizokuClient
    def inspect_run("async-run", _opts) do
      {:ok,
       %Snapshot{
         run_id: "async-run",
         workflow: "Checkout",
         queue: "approvals",
         status: :paused,
         reason: :manual_intervention_required,
         terminal?: false,
         terminal_status: nil,
         thread_revisions: %{run: 1, dispatch: 1},
         manual_state: %{
           kind: "approval",
           step: "review_order",
           paused_at: ~U[2026-07-11 14:45:00Z]
         }
       }}
    end

    @impl Kansoku.JizokuClient
    def inspect_run_graph(_run_id, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def explain_run(_run_id, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def cancel(_run_id, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def resume(_run_id, _attrs, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def approve(_run_id, _attrs, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def reject(_run_id, _attrs, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def replay(_run_id, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def start(_workflow, _payload, _opts), do: {:error, :unsupported}

    @impl Kansoku.JizokuClient
    def start_spec(_spec, _payload, _opts), do: {:error, :unsupported}
  end

  setup do
    previous_client = Application.get_env(:kansoku, :jizoku_client)

    on_exit(fn ->
      if previous_client do
        Application.put_env(:kansoku, :jizoku_client, previous_client)
      else
        Application.delete_env(:kansoku, :jizoku_client)
      end
    end)
  end

  test "renders manual actions and schedule declarations with run-detail navigation" do
    actions = [
      %ManualAction{
        run_id: "run-approval",
        workflow: "Checkout",
        queue: "approvals",
        step: "review_order",
        kind: "approval",
        reason: "operator review",
        status: "pending",
        waiting_since: ~U[2026-07-11 14:45:00Z],
        waiting_duration_seconds: 900,
        last_event_summary: "operator review"
      }
    ]

    schedules = [
      %Schedule{
        workflow: ScheduledCheckout,
        trigger: :nightly_checkout,
        expression: "0 2 * * *",
        timezone: "Etc/UTC"
      }
    ]

    html = render_queues(actions, schedules)

    assert html =~ "Manual actions"
    assert html =~ "review_order"
    assert html =~ "operator review"
    assert html =~ "15 minutes"
    assert html =~ ~s(href="/kansoku/runs/run-approval")
    assert html =~ ~s(id="manual-action-link-run-approval")
    assert html =~ "Schedules"
    assert html =~ "nightly_checkout"
    assert html =~ "0 2 * * *"
    assert html =~ "Host-owned"
    refute html =~ "must-not-render"
  end

  test "renders useful empty states without implementation details" do
    html = render_queues([], [])

    assert html =~ "No runs are waiting for manual action."
    assert html =~ "No schedules are configured for this operator surface."
    refute html =~ "API"
    refute html =~ "projection"
  end

  test "renders a safe load error" do
    manual_actions =
      AsyncResult.failed(%AsyncResult{}, {:missing_config, [:journal_storage]})

    schedules = [
      %Schedule{
        workflow: ScheduledCheckout,
        trigger: :nightly_checkout,
        expression: "0 2 * * *",
        timezone: "Etc/UTC"
      }
    ]

    html = render_queues([], schedules, manual_actions)

    assert html =~ "Unable to load operator queues"
    assert html =~ "nightly_checkout"
    assert html =~ "0 2 * * *"
    refute html =~ "journal_storage"
  end

  test "mounts, streams, and refreshes manual actions through the connected lifecycle" do
    Application.put_env(:kansoku, :jizoku_client, AsyncClient)

    assert {:ok, mounted_socket} = OperatorQueuesLive.mount(%{}, %{}, connected_socket())
    assert mounted_socket.assigns.manual_actions.loading

    loaded_socket = receive_stream_result(mounted_socket)
    assert loaded_socket.assigns.manual_actions.ok?

    rendered = OperatorQueuesLive.render(loaded_socket.assigns)
    html = rendered_to_string(rendered)
    assert html =~ "async-run"
    assert html =~ "review_order"

    assert {:noreply, refreshing_socket} =
             OperatorQueuesLive.handle_event("refresh", %{}, loaded_socket)

    assert refreshing_socket.assigns.manual_actions.loading
    assert receive_stream_result(refreshing_socket).assigns.manual_actions.ok?
  end

  defp render_queues(actions, schedules, manual_actions \\ AsyncResult.ok(true)) do
    stream =
      LiveStream.new(:manual_actions, 0, actions, dom_id: &"manual-action-#{&1.run_id}")

    %{
      prefix: "/kansoku",
      theme: :system,
      schedules: schedules,
      manual_actions: manual_actions,
      streams: %{manual_actions: stream}
    }
    |> OperatorQueuesLive.render()
    |> rendered_to_string()
  end

  defp connected_socket do
    %Socket{
      view: OperatorQueuesLive,
      transport_pid: self(),
      root_pid: self(),
      private: %{lifecycle: %Lifecycle{}, live_temp: %{}},
      assigns: %{
        __changed__: %{},
        flash: %{},
        prefix: "/kansoku",
        runtime_specs: nil,
        runtime_spec: nil,
        visibility_actor: "operator-1",
        visibility_policy: :operator
      }
    }
  end

  defp receive_stream_result(socket) do
    assert_receive {:phoenix, :async_result, {:stream, {ref, nil, :manual_actions, result}}},
                   1_000

    Async.handle_async(socket, nil, :stream, :manual_actions, ref, result)
  end
end
