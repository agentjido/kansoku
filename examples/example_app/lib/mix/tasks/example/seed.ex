defmodule Mix.Tasks.Example.Seed do
  @moduledoc """
  Seeds monitorable Squidie runs for the example app.
  """

  use Mix.Task

  @shortdoc "Seeds example Squidie workflow runs"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    reset_example_state!()

    started_runs =
      scenarios()
      |> Enum.flat_map(&start_scenario/1)

    run_ids = Enum.map(started_runs, & &1.run_id)

    drain_runtime(run_ids, 12)
    record_dynamic_work_overlay!(started_runs)

    runs =
      Enum.map(run_ids, fn run_id ->
        {:ok, run} = Squidie.inspect_run(run_id)
        run
      end)

    Mix.shell().info("""

    Seeded Squidie example runs.

    Current run statuses:
    #{format_runs(runs)}

    Open /sonar in the example app to inspect them.
    """)
  end

  defp scenarios do
    unique = System.system_time(:millisecond)

    [
      {SquidSonarExample.Workflows.CompletedCheckout, :completed_checkout,
       %{order_id: "order-complete-#{unique}", customer_id: "cust_demo"}},
      {SquidSonarExample.Workflows.FailingCheckout, :failing_checkout,
       %{order_id: "order-failed-#{unique}", customer_id: "cust_demo"}},
      {SquidSonarExample.Workflows.SagaCheckout, :saga_checkout,
       %{order_id: "order-saga-#{unique}", customer_id: "cust_demo"}},
      {SquidSonarExample.Workflows.RetryingCheckout, :retrying_checkout,
       %{order_id: "order-retrying-#{unique}", customer_id: "cust_demo"}},
      {SquidSonarExample.Workflows.PausedCheckout, :paused_checkout,
       %{order_id: "order-paused-#{unique}", customer_id: "cust_demo"}},
      {SquidSonarExample.Workflows.ManualReviewCheckout, :manual_review_checkout,
       %{order_id: "order-review-#{unique}", customer_id: "cust_demo"}}
    ]
  end

  defp start_scenario({workflow, trigger, payload}) do
    case Squidie.start(workflow, payload, trigger: trigger) do
      {:ok, run} ->
        Mix.shell().info("* started #{inspect(workflow)} #{run.run_id}")
        [%{run_id: run.run_id, workflow: workflow, trigger: trigger}]

      {:error, reason} ->
        Mix.shell().error("* failed #{inspect(workflow)}: #{inspect(reason)}")
        []
    end
  end

  defp record_dynamic_work_overlay!(started_runs) do
    case Enum.find(started_runs, &(&1.trigger == :paused_checkout)) do
      %{run_id: run_id} ->
        with {:ok, run} <- Squidie.inspect_run(run_id),
             {:ok, origin} <- dynamic_origin(run, "load_order"),
             {:ok, _updated_run} <-
               Squidie.record_dynamic_work(run_id, dynamic_work_overlay(origin)) do
          :ok
        else
          {:error, reason} ->
            raise "example seed dynamic work overlay failed: #{inspect(reason)}"
        end

      nil ->
        raise "example seed dynamic work overlay failed: paused checkout run missing"
    end
  end

  defp dynamic_origin(run, step) do
    run.attempts
    |> Enum.find(&(Map.get(&1, :step) == step and Map.get(&1, :applied?)))
    |> case do
      %{runnable_key: runnable_key, attempt_number: attempt_number} ->
        {:ok, %{runnable_key: runnable_key, step: step, attempt: attempt_number}}

      _missing ->
        {:error, {:dynamic_origin, :missing_applied_step}}
    end
  end

  defp dynamic_work_overlay(origin) do
    %{
      dynamic_key: "fraud_review",
      origin: origin,
      reason: :operator_inspection,
      nodes: [
        %{
          id: "fraud_review",
          action: "review_risk",
          metadata: %{queue: "risk"}
        }
      ]
    }
  end

  defp reset_example_state! do
    {:ok, _result} =
      SquidSonarExample.Repo.query("""
      TRUNCATE squidie_journal_entries,
               squidie_journal_checkpoints,
               squidie_journal_threads
      RESTART IDENTITY CASCADE
      """)
  end

  defp drain_runtime(run_ids, 0) do
    runs = inspect_runs(run_ids)

    if Enum.all?(runs, &settled_status?/1) do
      :ok
    else
      raise "example seed runtime drain exhausted: unsettled runs: #{inspect(runs)}"
    end
  end

  defp drain_runtime(run_ids, attempts_remaining) when attempts_remaining > 0 do
    runs = inspect_runs(run_ids)

    if Enum.all?(runs, &settled_status?/1) do
      :ok
    else
      case Squidie.execute_next(owner_id: "squid-sonar-example-seed") do
        {:ok, :none} ->
          Process.sleep(50)
          drain_runtime(run_ids, attempts_remaining - 1)

        {:ok, _snapshot} ->
          drain_runtime(run_ids, attempts_remaining - 1)

        {:error, reason} ->
          raise "example seed runtime drain failed: #{inspect(reason)}"
      end
    end
  end

  defp inspect_runs(run_ids) do
    Enum.map(run_ids, fn run_id ->
      {:ok, run} = Squidie.inspect_run(run_id)
      run
    end)
  end

  defp settled_status?(%{status: :running, reason: :attempt_scheduled_for_later}), do: true

  defp settled_status?(%{status: status})
       when status in [:completed, :failed, :retrying, :paused],
       do: true

  defp settled_status?(_run), do: false

  defp format_runs(runs) do
    runs
    |> Enum.map_join("\n", fn run ->
      "  * #{inspect(run.workflow)} #{display_status(run)} queue=#{inspect(run.queue)} reason=#{inspect(run.reason)} planned=#{length(run.planned_runnable_keys)}"
    end)
  end

  defp display_status(%{status: :running, reason: :attempt_scheduled_for_later}),
    do: :retrying

  defp display_status(%{status: status}), do: status
end
