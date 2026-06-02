defmodule SquidSonar.ReadModelFixtures do
  alias SquidMesh.ReadModel.Explanation.Diagnostic
  alias SquidMesh.ReadModel.Inspection.Snapshot
  alias SquidMesh.Runs.GraphInspection
  alias SquidMesh.Runs.GraphInspection.Edge
  alias SquidMesh.Runs.GraphInspection.Node

  def snapshot(status, attrs) do
    workflow = Keyword.fetch!(attrs, :workflow)

    %Snapshot{
      run_id: Keyword.get(attrs, :run_id, "run-#{status}"),
      workflow: workflow,
      trigger: "manual",
      input: Keyword.get(attrs, :input, %{"order_id" => "order-1"}),
      context: Keyword.get(attrs, :context, %{"attempted" => true}),
      queue: Keyword.get(attrs, :queue, "default"),
      status: status,
      reason: Keyword.get(attrs, :reason, :attempt_visible),
      terminal?: Keyword.get(attrs, :terminal?, status in [:completed, :failed, :cancelled]),
      terminal_status:
        Keyword.get(attrs, :terminal_status, if(status == :completed, do: :completed, else: nil)),
      thread_revisions: Keyword.get(attrs, :thread_revisions, %{run: 3, dispatch: 4}),
      planned_runnables: Keyword.get(attrs, :planned_runnables, []),
      planned_runnable_keys: Keyword.get(attrs, :planned_runnable_keys, []),
      applied_runnable_keys: Keyword.get(attrs, :applied_runnable_keys, []),
      pending_dispatches: Keyword.get(attrs, :pending_dispatches, []),
      pending_results: Keyword.get(attrs, :pending_results, []),
      visible_attempts: Keyword.get(attrs, :visible_attempts, []),
      scheduled_attempts: Keyword.get(attrs, :scheduled_attempts, []),
      next_visible_at: Keyword.get(attrs, :next_visible_at),
      deadline: Keyword.get(attrs, :deadline),
      expired_claims: Keyword.get(attrs, :expired_claims, []),
      attempts: Keyword.get(attrs, :attempts, []),
      anomalies: Keyword.get(attrs, :anomalies, []),
      manual_state: Keyword.get(attrs, :manual_state)
    }
  end

  def diagnostic(status, attrs) do
    workflow = Keyword.fetch!(attrs, :workflow)

    %Diagnostic{
      run_id: Keyword.get(attrs, :run_id, "run-#{status}"),
      workflow: workflow,
      queue: "default",
      status: status,
      reason: Keyword.get(attrs, :reason, :attempt_visible),
      step: Keyword.get(attrs, :step),
      summary: Keyword.get(attrs, :summary, "summary"),
      details: Keyword.get(attrs, :details, %{}),
      next_actions: Keyword.get(attrs, :next_actions, []),
      evidence: Keyword.get(attrs, :evidence, %{}),
      definition_version: Keyword.get(attrs, :definition_version, 1)
    }
  end

  def graph_inspection(status, attrs) do
    workflow = Keyword.fetch!(attrs, :workflow)

    %GraphInspection{
      run_id: Keyword.get(attrs, :run_id, "run-#{status}"),
      workflow: workflow,
      source: :read_model,
      status: status,
      current_node_id: Keyword.get(attrs, :current_node_id),
      current_node_ids: List.wrap(Keyword.get(attrs, :current_node_id)),
      terminal?: Keyword.get(attrs, :terminal?, status in [:completed, :failed, :cancelled]),
      nodes: Keyword.get(attrs, :nodes, []),
      edges: Keyword.get(attrs, :edges, []),
      anomalies: Keyword.get(attrs, :anomalies, [])
    }
  end

  def graph_node(id, status, current?, attrs \\ []) do
    %Node{
      id: id,
      status: status,
      current?: current?,
      input: Keyword.get(attrs, :input),
      output: Keyword.get(attrs, :output),
      error: Keyword.get(attrs, :error),
      deadline: Keyword.get(attrs, :deadline),
      recovery: Keyword.get(attrs, :recovery),
      transition: Keyword.get(attrs, :transition),
      manual_state: Keyword.get(attrs, :manual_state),
      attempts: []
    }
  end

  def graph_edge(from, to, outcome, attrs \\ []) do
    %Edge{
      id: "#{from}:#{outcome}:#{to}",
      from: from,
      to: to,
      type: edge_type(outcome),
      status: :pending,
      outcome: outcome,
      condition: nil,
      recovery: Keyword.get(attrs, :recovery)
    }
  end

  def edge_type(:ready), do: :dependency
  def edge_type(_outcome), do: :transition

  def compensation_recovery(callback, attrs \\ []) do
    recovery = %{
      compensation: %{
        callback: callback,
        status: Keyword.get(attrs, :status, :available)
      }
    }

    maybe_put(recovery, :failure, Keyword.get(attrs, :failure))
  end

  def recovery_policy_evidence(step, recovery) do
    recovery_policy_evidence(%{to_string(step) => recovery})
  end

  def recovery_policy_evidence(recovery_policies) when is_map(recovery_policies) do
    %{
      recovery_policies:
        Map.new(recovery_policies, fn {step, recovery} ->
          {to_string(step), recovery}
        end)
    }
  end

  def attempt(step, status, attempt_number, error, attrs \\ []) do
    %{
      step: step,
      status: status,
      attempt_number: attempt_number,
      error: error
    }
    |> maybe_put(:deadline, Keyword.get(attrs, :deadline))
    |> maybe_put(:recovery, Keyword.get(attrs, :recovery))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
