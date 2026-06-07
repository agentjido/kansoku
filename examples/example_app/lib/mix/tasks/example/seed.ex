defmodule Mix.Tasks.Example.Seed do
  @moduledoc """
  Seeds monitorable Squidie runs for the example app.
  """

  use Mix.Task

  @shortdoc "Seeds example Squidie workflow runs"
  @drain_timeout_ms 5_000
  @drain_idle_sleep_ms 50

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    reset_example_state!()

    started_runs =
      scenarios()
      |> Enum.flat_map(&start_scenario/1)

    run_ids = Enum.map(started_runs, & &1.run_id)

    drain_runtime(run_ids, drain_deadline())
    dynamic_work_demo = record_dynamic_work_overlay!(started_runs)
    compensation_demo = compensation_evidence_demo!(started_runs)
    deferred_demo = deferred_continuation_demo!(started_runs)

    runs =
      Enum.map(run_ids, fn run_id ->
        {:ok, run} = Squidie.inspect_run(run_id)
        run
      end)

    Mix.shell().info("""

    Seeded Squidie example runs.

    Current run statuses:
    #{format_runs(runs)}

    Dynamic work overlay demo:
    #{format_dynamic_work_demo(dynamic_work_demo)}

    Compensation evidence demo:
    #{format_compensation_demo(compensation_demo)}

    Deferred continuation demo:
    #{format_deferred_demo(deferred_demo)}

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
      {SquidSonarExample.Workflows.DeferredCheckout, :deferred_checkout,
       %{order_id: "order-deferred-#{unique}", customer_id: "cust_demo"}},
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
             dynamic_work = dynamic_work_overlay(origin),
             {:ok, _updated_run} <- Squidie.record_dynamic_work(run_id, dynamic_work),
             {:ok, graph} <- Squidie.inspect_run_graph(run_id),
             overlay when is_map(overlay) <- dynamic_work_overlay_for(graph, "fraud_review") do
          %{run_id: run_id, overlay: overlay}
        else
          {:error, reason} ->
            raise "example seed dynamic work overlay failed: #{inspect(reason)}"

          _missing ->
            raise "example seed dynamic work overlay failed: overlay missing from graph inspection"
        end

      nil ->
        raise "example seed dynamic work overlay failed: paused checkout run missing"
    end
  end

  defp compensation_evidence_demo!(started_runs) do
    case Enum.find(started_runs, &(&1.trigger == :saga_checkout)) do
      %{run_id: run_id} ->
        with {:ok, graph} <- Squidie.inspect_run_graph(run_id),
             [_node | _rest] = nodes <- compensation_nodes(graph) do
          %{run_id: run_id, nodes: nodes}
        else
          {:error, reason} ->
            raise "example seed compensation evidence failed: #{inspect(reason)}"

          [] ->
            raise "example seed compensation evidence failed: compensation nodes missing"
        end

      nil ->
        raise "example seed compensation evidence failed: saga checkout run missing"
    end
  end

  defp deferred_continuation_demo!(started_runs) do
    case Enum.find(started_runs, &(&1.trigger == :deferred_checkout)) do
      %{run_id: run_id} ->
        with {:ok, run} <- Squidie.inspect_run(run_id),
             %{reason: :deferred_continuation} <- run,
             [attempt | _rest] <- deferred_attempts(run),
             {:ok, graph} <- Squidie.inspect_run_graph(run_id),
             [_node | _rest] = nodes <- deferred_nodes(graph) do
          %{run_id: run_id, attempt: attempt, nodes: nodes}
        else
          {:error, reason} ->
            raise "example seed deferred continuation failed: #{inspect(reason)}"

          %{reason: reason} ->
            raise "example seed deferred continuation failed: expected deferred run, got #{inspect(reason)}"

          [] ->
            raise "example seed deferred continuation failed: deferred attempts or nodes missing"
        end

      nil ->
        raise "example seed deferred continuation failed: deferred checkout run missing"
    end
  end

  defp compensation_nodes(graph) do
    graph.nodes
    |> Enum.filter(fn node ->
      node
      |> Map.get(:id)
      |> compensation_node_id?()
    end)
  end

  defp compensation_node_id?("compensate:" <> _origin), do: true
  defp compensation_node_id?(_id), do: false

  defp deferred_attempts(run) do
    run.scheduled_attempts
    |> Enum.filter(fn attempt ->
      attempt
      |> Map.get(:deferred)
      |> is_map()
    end)
  end

  defp deferred_nodes(graph) do
    graph.nodes
    |> Enum.filter(&(Map.get(&1, :status) == :deferred))
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
          metadata: %{queue: "risk", owner: "ops"}
        }
      ],
      metadata: %{
        note: "seeded overlay for the Squid Sonar dynamic work panel"
      }
    }
  end

  defp dynamic_work_overlay_for(graph, dynamic_key) do
    graph.dynamic_work_overlays
    |> Enum.find(&(Map.get(&1, :dynamic_key) == dynamic_key))
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

  defp drain_deadline do
    System.monotonic_time(:millisecond) + @drain_timeout_ms
  end

  defp drain_runtime(run_ids, deadline_ms) do
    runs = inspect_runs(run_ids)
    unsettled_runs = Enum.reject(runs, &settled_status?/1)

    cond do
      unsettled_runs == [] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline_ms ->
        raise "example seed runtime drain exhausted:\n#{format_runs(unsettled_runs)}"

      true ->
        case Squidie.execute_next(owner_id: "squid-sonar-example-seed") do
          {:ok, :none} ->
            Process.sleep(@drain_idle_sleep_ms)
            drain_runtime(run_ids, deadline_ms)

          {:ok, _snapshot} ->
            drain_runtime(run_ids, deadline_ms)

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
  defp settled_status?(%{status: :running, reason: :deferred_continuation}), do: true

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

  defp display_status(%{status: :running, reason: :deferred_continuation}),
    do: :deferred

  defp display_status(%{status: status}), do: status

  defp format_dynamic_work_demo(%{run_id: run_id, overlay: overlay}) do
    dynamic_key = Map.get(overlay, :dynamic_key)
    origin_node_id = Map.get(overlay, :origin_node_id)
    added_node_ids = Map.get(overlay, :added_node_ids, [])
    added_edge_ids = Map.get(overlay, :added_edge_ids, [])

    "  * #{dynamic_key} run=#{run_id} origin=#{origin_node_id} nodes=#{inspect(added_node_ids)} edges=#{inspect(added_edge_ids)}"
  end

  defp format_compensation_demo(%{run_id: run_id, nodes: nodes}) do
    nodes =
      nodes
      |> Enum.map_join(", ", fn node ->
        "#{Map.get(node, :id)} status=#{inspect(Map.get(node, :status))}"
      end)

    "  * run=#{run_id} nodes=#{nodes}"
  end

  defp format_deferred_demo(%{run_id: run_id, attempt: attempt, nodes: nodes}) do
    node_ids =
      nodes
      |> Enum.map_join(", ", &Map.get(&1, :id))

    deferred = Map.get(attempt, :deferred, %{})
    reason = deferred |> Map.get(:reason, %{}) |> Map.get(:message)

    "  * run=#{run_id} step=#{Map.get(attempt, :step)} reason=#{inspect(reason)} visible_at=#{inspect(Map.get(attempt, :visible_at))} nodes=#{node_ids}"
  end
end
