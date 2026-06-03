defmodule SquidSonarExample.JournalRunTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias SquidSonarExample.Repo
  alias SquidSonarExample.Workflows.ManualReviewCheckout

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    reset_example_state!()

    :ok
  end

  test "drains approval follow-up work scheduled by manual review decisions" do
    {:ok, run} =
      Squidie.start(
        ManualReviewCheckout,
        %{order_id: "order-review-test", customer_id: "cust_demo"},
        trigger: :manual_review_checkout
      )

    assert {:ok, _snapshot} = Squidie.execute_next(owner_id: "squid-sonar-example-test")

    assert {:ok, paused_run} = await_status(run.run_id, :paused)
    assert %{step: "wait_for_review", kind: "approval"} = paused_run.manual_state

    {:ok, approved_run} =
      Squidie.approve(run.run_id, %{actor: "ops_test", comment: "approved"})

    assert approved_run.status == :running
    assert Enum.any?(approved_run.planned_runnable_keys, &String.contains?(&1, "record_approval"))

    start_supervised!(
      {SquidSonarExample.JournalRun,
       name: SquidSonarExample.JournalRunTestWorker,
       owner_id: "squid-sonar-example-test",
       idle_interval_ms: 10}
    )

    assert {:ok, completed_run} = await_status(run.run_id, :completed)
    assert completed_run.terminal?
  end

  defp await_status(run_id, expected_status, attempts_remaining \\ 20)

  defp await_status(run_id, expected_status, attempts_remaining) when attempts_remaining > 0 do
    {:ok, run} = Squidie.inspect_run(run_id)

    if run.status == expected_status do
      {:ok, run}
    else
      Process.sleep(25)
      await_status(run_id, expected_status, attempts_remaining - 1)
    end
  end

  defp await_status(run_id, _expected_status, 0), do: Squidie.inspect_run(run_id)

  defp reset_example_state! do
    {:ok, _result} =
      Repo.query("""
      TRUNCATE squidie_journal_entries,
               squidie_journal_checkpoints,
               squidie_journal_threads
      RESTART IDENTITY CASCADE
      """)
  end
end
