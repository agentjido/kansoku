defmodule SquidSonar.Runs.RunDetail do
  @moduledoc """
  Detailed run projection for the run detail view.
  """

  alias Squidie.ReadModel.Explanation.Diagnostic
  alias Squidie.ReadModel.Inspection.Snapshot
  alias Squidie.Runs.GraphInspection
  alias SquidSonar.Runs.WorkflowGraph

  defmodule Summary do
    @moduledoc false

    @type t :: %__MODULE__{
            id: String.t(),
            workflow: String.t() | module() | nil,
            queue: String.t(),
            status: atom(),
            current_step: String.t() | nil,
            reason: atom(),
            terminal?: boolean(),
            terminal_status: atom() | nil,
            deadline: map() | nil,
            thread_revisions: %{run: non_neg_integer(), dispatch: non_neg_integer()}
          }

    @enforce_keys [
      :id,
      :workflow,
      :queue,
      :status,
      :current_step,
      :reason,
      :terminal?,
      :terminal_status,
      :deadline,
      :thread_revisions
    ]

    defstruct [
      :id,
      :workflow,
      :queue,
      :status,
      :current_step,
      :reason,
      :terminal?,
      :terminal_status,
      :deadline,
      :thread_revisions
    ]
  end

  defmodule RecoveryPolicy do
    @moduledoc false

    @type t :: %__MODULE__{
            step: String.t(),
            compensation_callback: String.t() | nil,
            compensation_status: atom() | String.t() | nil,
            irreversible?: boolean() | nil,
            compensatable?: boolean() | nil,
            replay: atom() | String.t() | nil,
            recovery: atom() | String.t() | nil
          }

    @enforce_keys [:step]

    defstruct [
      :step,
      :compensation_callback,
      :compensation_status,
      :irreversible?,
      :compensatable?,
      :replay,
      :recovery
    ]
  end

  defmodule CompensationEvidence do
    @moduledoc false

    @type t :: %__MODULE__{
            step: String.t(),
            compensation_callback: String.t() | nil,
            policy_status: atom() | String.t() | nil,
            status: atom() | String.t(),
            compensation_step: String.t() | nil,
            failure_reason: String.t() | nil,
            irreversible?: boolean() | nil,
            compensatable?: boolean() | nil,
            replay: atom() | String.t() | nil,
            recovery: atom() | String.t() | nil
          }

    @enforce_keys [:step, :status]

    defstruct [
      :step,
      :status,
      :compensation_callback,
      :policy_status,
      :compensation_step,
      :failure_reason,
      :irreversible?,
      :compensatable?,
      :replay,
      :recovery
    ]
  end

  defmodule DynamicWorkOverlay do
    @moduledoc false

    @type t :: %__MODULE__{
            dynamic_key: String.t() | nil,
            status: atom() | String.t() | nil,
            reason: atom() | String.t() | nil,
            origin: map() | nil,
            origin_node_id: String.t() | nil,
            added_node_ids: [String.t()],
            added_edge_ids: [String.t()],
            node_count: non_neg_integer(),
            edge_count: non_neg_integer(),
            recorded_at: DateTime.t() | NaiveDateTime.t() | String.t() | nil
          }

    defstruct [
      :dynamic_key,
      :status,
      :reason,
      :origin,
      :origin_node_id,
      :recorded_at,
      added_node_ids: [],
      added_edge_ids: [],
      node_count: 0,
      edge_count: 0
    ]
  end

  @type t :: %__MODULE__{
          summary: Summary.t(),
          payload: map() | nil,
          context: map(),
          last_error: map() | nil,
          planned_runnables: [map()],
          attempts: [map()],
          anomalies: [map()],
          graph_inspection: map(),
          workflow_graph: WorkflowGraph.t(),
          explanation: Diagnostic.t(),
          recovery_policies: [RecoveryPolicy.t()],
          compensation_evidence: [CompensationEvidence.t()],
          dynamic_work: [map()],
          dynamic_work_overlays: [DynamicWorkOverlay.t()]
        }

  defstruct [
    :summary,
    :payload,
    :context,
    :last_error,
    :explanation,
    :graph_inspection,
    :workflow_graph,
    recovery_policies: [],
    compensation_evidence: [],
    dynamic_work: [],
    dynamic_work_overlays: [],
    planned_runnables: [],
    attempts: [],
    anomalies: []
  ]

  @doc false
  @spec from_models(Snapshot.t(), Diagnostic.t(), GraphInspection.t()) :: t()
  def from_models(%Snapshot{} = snapshot, %Diagnostic{} = explanation, %GraphInspection{} = graph) do
    graph_inspection = GraphInspection.to_map(graph)

    recovery_policies = recovery_policies(explanation)

    %__MODULE__{
      summary: summary(snapshot, explanation, graph),
      payload: snapshot.input,
      context: snapshot.context,
      last_error: latest_error(snapshot.attempts),
      planned_runnables: List.wrap(snapshot.planned_runnables),
      attempts: List.wrap(snapshot.attempts),
      anomalies: List.wrap(snapshot.anomalies),
      graph_inspection: graph_inspection,
      workflow_graph: WorkflowGraph.from_models(snapshot, graph),
      explanation: explanation,
      recovery_policies: recovery_policies,
      compensation_evidence: compensation_evidence(snapshot, recovery_policies),
      dynamic_work: graph.dynamic_work,
      dynamic_work_overlays: dynamic_work_overlays(graph.dynamic_work_overlays)
    }
  end

  defp summary(%Snapshot{} = snapshot, %Diagnostic{} = explanation, %GraphInspection{} = graph) do
    %Summary{
      id: snapshot.run_id,
      workflow: snapshot.workflow,
      queue: snapshot.queue,
      status: snapshot.status,
      current_step: graph.current_node_id || explanation.step,
      reason: snapshot.reason,
      terminal?: snapshot.terminal?,
      terminal_status: snapshot.terminal_status,
      deadline: snapshot.deadline,
      thread_revisions: snapshot.thread_revisions
    }
  end

  defp latest_error(attempts) do
    attempts
    |> List.wrap()
    |> Enum.reverse()
    |> Enum.find_value(fn attempt -> Map.get(attempt, :error) end)
  end

  defp recovery_policies(%Diagnostic{evidence: evidence}) when is_map(evidence) do
    case map_value(evidence, :recovery_policies) do
      policies when is_map(policies) ->
        policies
        |> Enum.map(fn {step, policy} -> recovery_policy(step, policy) end)
        |> Enum.sort_by(& &1.step)

      _missing ->
        []
    end
  end

  defp recovery_policies(_explanation), do: []

  defp recovery_policy(step, policy) when is_map(policy) do
    compensation = map_value(policy, :compensation)

    %RecoveryPolicy{
      step: to_string(step),
      compensation_callback: compensation_callback(compensation),
      compensation_status: compensation_status(compensation),
      irreversible?: map_value(policy, :irreversible?),
      compensatable?: map_value(policy, :compensatable?),
      replay: map_value(policy, :replay),
      recovery: map_value(policy, :recovery)
    }
  end

  defp recovery_policy(step, _policy), do: %RecoveryPolicy{step: to_string(step)}

  defp compensation_callback(compensation) when is_map(compensation) do
    case map_value(compensation, :callback) do
      nil ->
        nil

      callback ->
        callback
        |> to_string()
        |> String.replace_prefix("Elixir.", "")
    end
  end

  defp compensation_callback(_compensation), do: nil

  defp compensation_status(compensation) when is_map(compensation),
    do: map_value(compensation, :status)

  defp compensation_status(_compensation), do: nil

  defp compensation_evidence(%Snapshot{} = snapshot, recovery_policies) do
    policies_by_step =
      recovery_policies
      |> Enum.map(&compensation_policy_evidence/1)
      |> Enum.reduce(%{}, fn evidence, evidence_by_step ->
        Map.update(
          evidence_by_step,
          evidence.step,
          evidence,
          &merge_compensation_policy(&1, evidence)
        )
      end)

    snapshot
    |> compensation_sources()
    |> Enum.flat_map(&compensation_attempt_evidence/1)
    |> Enum.reduce(policies_by_step, fn attempt_evidence, evidence_by_step ->
      Map.update(
        evidence_by_step,
        attempt_evidence.step,
        attempt_evidence,
        &merge_compensation_evidence(&1, attempt_evidence)
      )
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.step)
  end

  defp compensation_policy_evidence(%RecoveryPolicy{} = policy) do
    {step, compensation_step} = compensation_step(policy.step)

    %CompensationEvidence{
      step: step,
      compensation_callback: policy.compensation_callback,
      policy_status: policy.compensation_status,
      status: compensation_policy_status(policy),
      compensation_step: compensation_step,
      irreversible?: policy.irreversible?,
      compensatable?: policy.compensatable?,
      replay: policy.replay,
      recovery: policy.recovery
    }
  end

  defp compensation_policy_status(%RecoveryPolicy{compensatable?: false}), do: :non_compensatable
  defp compensation_policy_status(%RecoveryPolicy{irreversible?: true}), do: :irreversible

  defp compensation_policy_status(%RecoveryPolicy{} = policy) do
    cond do
      policy.compensation_callback -> :eligible
      policy.recovery -> policy.recovery
      true -> :unknown
    end
  end

  defp compensation_attempt_evidence(attempt) when is_map(attempt) do
    step = map_value(attempt, :step)

    case string_or_nil(step) do
      "compensate:" <> origin_step ->
        [
          %CompensationEvidence{
            step: origin_step,
            status: compensation_source_status(attempt),
            compensation_step: "compensate:#{origin_step}",
            failure_reason: error_reason(map_value(attempt, :error))
          }
        ]

      _other ->
        []
    end
  end

  defp compensation_attempt_evidence(_attempt), do: []

  defp compensation_sources(%Snapshot{} = snapshot) do
    []
    |> source_entries(:pending_dispatch, snapshot.pending_dispatches)
    |> source_entries(:pending_result, snapshot.pending_results)
    |> source_entries(:visible_attempt, snapshot.visible_attempts)
    |> source_entries(:scheduled_attempt, snapshot.scheduled_attempts)
    |> source_entries(:expired_claim, snapshot.expired_claims)
    |> source_entries(:attempt, snapshot.attempts)
  end

  defp source_entries(entries, source, values) do
    source_values =
      values
      |> List.wrap()
      |> Enum.flat_map(fn
        value when is_map(value) -> [Map.put(value, :sonar_source, source)]
        _malformed -> []
      end)

    entries ++ source_values
  end

  defp compensation_source_status(source) do
    source
    |> map_value(:sonar_source)
    |> compensation_source_status(map_value(source, :status))
  end

  defp compensation_source_status(:pending_dispatch, _status), do: :pending_dispatch
  defp compensation_source_status(:pending_result, :completed), do: :result_pending_apply
  defp compensation_source_status(:pending_result, "completed"), do: :result_pending_apply
  defp compensation_source_status(:scheduled_attempt, _status), do: :scheduled
  defp compensation_source_status(:expired_claim, _status), do: :expired_claim
  defp compensation_source_status(_source, :completed), do: :succeeded
  defp compensation_source_status(_source, "completed"), do: :succeeded
  defp compensation_source_status(_source, :failed), do: :failed
  defp compensation_source_status(_source, "failed"), do: :failed
  defp compensation_source_status(_source, :skipped), do: :skipped
  defp compensation_source_status(_source, "skipped"), do: :skipped

  defp compensation_source_status(_source, status) when status in [:claimed, :running],
    do: :started

  defp compensation_source_status(_source, status) when status in ["claimed", "running"],
    do: :started

  defp compensation_source_status(_source, :retry_scheduled), do: :retrying
  defp compensation_source_status(_source, "retry_scheduled"), do: :retrying

  defp compensation_source_status(_source, status) when is_atom(status) or is_binary(status),
    do: status

  defp compensation_source_status(_source, _status), do: :unknown

  defp merge_compensation_evidence(
         %CompensationEvidence{} = policy,
         %CompensationEvidence{} = attempt
       ) do
    %CompensationEvidence{
      policy
      | status: attempt.status,
        compensation_step: attempt.compensation_step,
        failure_reason: attempt.failure_reason
    }
  end

  defp merge_compensation_policy(
         %CompensationEvidence{} = existing,
         %CompensationEvidence{} = incoming
       ) do
    %CompensationEvidence{
      existing
      | compensation_callback: existing.compensation_callback || incoming.compensation_callback,
        policy_status: existing.policy_status || incoming.policy_status,
        status: merged_policy_status(existing.status, incoming.status),
        compensation_step: existing.compensation_step || incoming.compensation_step,
        irreversible?: existing.irreversible? || incoming.irreversible?,
        compensatable?: existing.compensatable? || incoming.compensatable?,
        replay: existing.replay || incoming.replay,
        recovery: existing.recovery || incoming.recovery
    }
  end

  defp merged_policy_status(:unknown, status), do: status
  defp merged_policy_status(status, _incoming), do: status

  defp compensation_step("compensate:" <> origin_step = compensation_step),
    do: {origin_step, compensation_step}

  defp compensation_step(step), do: {step, nil}

  defp error_reason(nil), do: nil

  defp error_reason(error) when is_map(error) do
    case map_value(error, :code) do
      code when is_binary(code) -> code
      _other -> "present"
    end
  end

  defp error_reason(error) when is_binary(error), do: "present"
  defp error_reason(_error), do: "present"

  defp dynamic_work_overlays(overlays) when is_list(overlays) do
    Enum.flat_map(overlays, &dynamic_work_overlay/1)
  end

  defp dynamic_work_overlay(overlay) when is_map(overlay) do
    projected = %DynamicWorkOverlay{
      dynamic_key: string_or_nil(map_value(overlay, :dynamic_key)),
      status: map_value(overlay, :status),
      reason: map_value(overlay, :reason),
      origin: map_value(overlay, :origin),
      origin_node_id: string_or_nil(map_value(overlay, :origin_node_id)),
      added_node_ids: string_list(map_value(overlay, :added_node_ids)),
      added_edge_ids: string_list(map_value(overlay, :added_edge_ids)),
      node_count: count_value(map_value(overlay, :node_count)),
      edge_count: count_value(map_value(overlay, :edge_count)),
      recorded_at: map_value(overlay, :recorded_at)
    }

    if dynamic_work_overlay?(projected), do: [projected], else: []
  end

  defp dynamic_work_overlay(_overlay), do: []

  defp dynamic_work_overlay?(%DynamicWorkOverlay{} = overlay) do
    not is_nil(overlay.dynamic_key) or not is_nil(overlay.status) or not is_nil(overlay.reason) or
      not is_nil(overlay.origin_node_id) or overlay.added_node_ids != [] or
      overlay.added_edge_ids != [] or not is_nil(overlay.recorded_at)
  end

  defp string_list(values) when is_list(values) do
    values
    |> Enum.filter(&(is_binary(&1) or is_atom(&1)))
    |> Enum.map(&to_string/1)
  end

  defp string_list(_values), do: []

  defp string_or_nil(nil), do: nil
  defp string_or_nil(value) when is_binary(value) or is_atom(value), do: to_string(value)
  defp string_or_nil(_value), do: nil

  defp count_value(value) when is_integer(value) and value >= 0, do: value
  defp count_value(_value), do: 0

  defp map_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end
end
