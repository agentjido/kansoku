defmodule SquidSonar.OperatorQueuesTest do
  use ExUnit.Case, async: true

  import SquidSonar.ReadModelFixtures

  alias Squidie.ReadModel.Listing.Summary
  alias SquidSonar.FakeSquidieClient
  alias SquidSonar.OperatorQueues

  defmodule VisibilityPolicy do
    @spec visibility_scope(map(), map()) :: :operator
    def visibility_scope(actor, view) do
      send(actor.test_pid, {:visibility_checked, view.run_id})
      :operator
    end
  end

  defmodule ScheduledWorkflow do
    use Squidie.Workflow

    workflow do
      trigger :nightly_checkout do
        cron("0 2 * * *", timezone: "Etc/UTC")
      end

      step(:reconcile, :log, message: "reconcile")
      transition(:reconcile, on: :ok, to: :complete)
    end
  end

  @now ~U[2026-07-11 15:00:00Z]

  test "lists every currently waiting manual action through the visibility boundary" do
    FakeSquidieClient.put_list_runs(
      {:ok,
       [
         summary("approval-run", :paused, "approvals"),
         summary("pause-run", :paused, "operations")
       ]}
    )

    FakeSquidieClient.put_inspect_run(fn run_id, _opts ->
      manual_state =
        case run_id do
          "approval-run" ->
            %{
              kind: "approval",
              step: "review_order",
              status: "pending",
              reason: "operator review",
              paused_at: ~U[2026-07-11 14:45:00Z],
              metadata: %{secret: "must-not-render"}
            }

          "pause-run" ->
            %{
              kind: "pause",
              step: "confirm_inventory",
              status: "pending",
              reason: "inventory check",
              paused_at: ~U[2026-07-11 14:30:00Z]
            }
        end

      {:ok,
       snapshot(:paused,
         run_id: run_id,
         workflow: "Checkout",
         queue: if(run_id == "approval-run", do: "approvals", else: "operations"),
         terminal?: false,
         manual_state: manual_state,
         input: %{"secret" => "must-not-render"},
         context: %{"secret" => "must-not-render"}
       )}
    end)

    assert {:ok, actions} =
             OperatorQueues.list_manual_actions(
               client: FakeSquidieClient,
               now: @now,
               visibility_actor: %{test_pid: self()},
               visibility_policy: VisibilityPolicy
             )

    assert Enum.map(actions, & &1.run_id) == ["approval-run", "pause-run"]
    assert Enum.map(actions, & &1.kind) == ["approval", "pause"]
    assert Enum.map(actions, & &1.waiting_duration_seconds) == [900, 1_800]
    assert Enum.all?(actions, &(&1.workflow == "Checkout"))
    assert Enum.all?(actions, &(not Map.has_key?(Map.from_struct(&1), :metadata)))
    assert_received {:visibility_checked, "approval-run"}
    assert_received {:visibility_checked, "pause-run"}
  end

  test "drops stale paused summaries that no longer have a manual boundary" do
    FakeSquidieClient.put_list_runs({:ok, [summary("resolved-run", :paused, "default")]})

    FakeSquidieClient.put_inspect_run(
      {:ok,
       snapshot(:running,
         run_id: "resolved-run",
         workflow: "Checkout",
         terminal?: false,
         manual_state: nil
       )}
    )

    assert {:ok, []} =
             OperatorQueues.list_manual_actions(
               client: FakeSquidieClient,
               now: @now,
               visibility_actor: %{},
               visibility_policy: :operator
             )
  end

  test "projects host-approved cron declarations without inventing scheduler state" do
    specs = [
      nightly: %{
        workflow: ScheduledCheckout,
        triggers: [
          %{
            name: :nightly_checkout,
            type: :cron,
            config: %{expression: "0 2 * * *", timezone: "Etc/UTC"},
            payload: []
          },
          %{name: :manual_checkout, type: :manual, config: %{}, payload: []}
        ]
      }
    ]

    assert [schedule] = OperatorQueues.list_schedules(specs)
    assert schedule.workflow == ScheduledCheckout
    assert schedule.trigger == :nightly_checkout
    assert schedule.expression == "0 2 * * *"
    assert schedule.timezone == "Etc/UTC"
    assert schedule.last_observed_run == nil
    assert schedule.next_intended_window == nil
    assert schedule.status == :host_owned
  end

  test "projects cron declarations from Squidie workflow modules" do
    assert [schedule] = OperatorQueues.list_schedules(nightly: ScheduledWorkflow)
    assert schedule.workflow == ScheduledWorkflow
    assert schedule.trigger == :nightly_checkout
    assert schedule.expression == "0 2 * * *"
    assert schedule.timezone == "Etc/UTC"
  end

  test "projects a single runtime workflow spec" do
    spec = %{
      workflow: ScheduledWorkflow,
      triggers: [
        %{
          name: :nightly_checkout,
          type: :cron,
          config: %{expression: "0 2 * * *", timezone: "Etc/UTC"}
        }
      ]
    }

    assert [%{trigger: :nightly_checkout}] = OperatorQueues.list_schedules(spec)
  end

  test "returns a safe error when listing or redaction fails" do
    FakeSquidieClient.put_list_runs({:error, {:missing_config, [:journal_storage]}})

    assert {:error, {:missing_config, [:journal_storage]}} =
             OperatorQueues.list_manual_actions(
               client: FakeSquidieClient,
               visibility_actor: %{},
               visibility_policy: :operator
             )
  end

  test "fails closed when the manual queue visibility policy is invalid" do
    FakeSquidieClient.put_list_runs({:ok, [summary("restricted-run", :paused, "default")]})

    FakeSquidieClient.put_inspect_run(
      {:ok,
       snapshot(:paused,
         run_id: "restricted-run",
         workflow: "Checkout",
         terminal?: false,
         manual_state: %{kind: "approval", step: "review"}
       )}
    )

    assert {:error, {:invalid_visibility_policy, :missing_callback}} =
             OperatorQueues.list_manual_actions(
               client: FakeSquidieClient,
               visibility_actor: "operator-1",
               visibility_policy: __MODULE__
             )
  end

  defp summary(run_id, status, queue) do
    %Summary{
      run_id: run_id,
      workflow: "Checkout",
      definition_version: "1",
      queue: queue,
      status: status,
      terminal?: false,
      terminal_status: nil,
      deadline: nil,
      indexed_at: @now,
      thread_revision: 1,
      anomalies: []
    }
  end
end
