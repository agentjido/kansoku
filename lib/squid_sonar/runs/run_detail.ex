defmodule SquidSonar.Runs.RunDetail do
  @moduledoc """
  Detailed run projection for the run detail view.
  """

  alias SquidMesh.ReadModel.Explanation.Diagnostic
  alias SquidMesh.ReadModel.Inspection.Snapshot
  alias SquidMesh.Runs.GraphInspection
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
          recovery_policies: [RecoveryPolicy.t()]
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
    planned_runnables: [],
    attempts: [],
    anomalies: []
  ]

  @doc false
  @spec from_models(Snapshot.t(), Diagnostic.t(), GraphInspection.t()) :: t()
  def from_models(%Snapshot{} = snapshot, %Diagnostic{} = explanation, %GraphInspection{} = graph) do
    %__MODULE__{
      summary: summary(snapshot, explanation, graph),
      payload: snapshot.input,
      context: snapshot.context,
      last_error: latest_error(snapshot.attempts),
      planned_runnables: List.wrap(snapshot.planned_runnables),
      attempts: List.wrap(snapshot.attempts),
      anomalies: List.wrap(snapshot.anomalies),
      graph_inspection: GraphInspection.to_map(graph),
      workflow_graph: WorkflowGraph.from_models(snapshot, graph),
      explanation: explanation,
      recovery_policies: recovery_policies(explanation)
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

  defp map_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end
end
