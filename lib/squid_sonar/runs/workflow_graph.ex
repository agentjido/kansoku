defmodule SquidSonar.Runs.WorkflowGraph do
  @moduledoc """
  Workflow graph projection for run detail views.
  """

  alias SquidMesh.ReadModel.Inspection.Snapshot
  alias SquidMesh.Runs.GraphInspection
  alias SquidMesh.Workflow.Definition

  defmodule Node do
    @moduledoc false

    @type t :: %__MODULE__{
            name: atom() | String.t(),
            label: String.t(),
            status: atom(),
            current?: boolean(),
            terminal?: boolean(),
            deadline: map() | nil,
            recovery: map() | nil
          }

    defstruct [:name, :label, :status, :deadline, :recovery, current?: false, terminal?: false]
  end

  defmodule Edge do
    @moduledoc false

    @type t :: %__MODULE__{
            from: atom() | String.t(),
            to: atom() | String.t(),
            outcome: atom(),
            recovery: atom() | nil
          }

    defstruct [:from, :to, :outcome, :recovery]
  end

  @type t :: %__MODULE__{
          available?: boolean(),
          mode: :transition | :dependency | :history,
          nodes: [struct()],
          edges: [struct()]
        }

  defstruct available?: false, mode: :history, nodes: [], edges: []

  @doc false
  @spec from_models(Snapshot.t(), GraphInspection.t()) :: t()
  def from_models(%Snapshot{} = snapshot, %GraphInspection{} = graph_inspection) do
    definition = load_definition(snapshot.workflow)

    %__MODULE__{
      available?: graph_inspection.nodes != [],
      mode: graph_mode(definition),
      nodes: Enum.map(graph_inspection.nodes, &graph_node(&1, definition)),
      edges: Enum.map(graph_inspection.edges, &graph_edge/1)
    }
  end

  defp graph_mode({:ok, definition}) do
    if Definition.dependency_mode?(definition), do: :dependency, else: :transition
  end

  defp graph_mode(_definition), do: :history

  defp load_definition(workflow) when is_atom(workflow), do: Definition.load(workflow)

  defp load_definition(workflow) when is_binary(workflow) do
    case Definition.load_serialized(workflow) do
      {:ok, _workflow, definition} -> {:ok, definition}
      {:error, _reason} = error -> error
    end
  end

  defp load_definition(_workflow), do: {:error, {:invalid_workflow, nil}}

  defp graph_node(%{id: id, status: status, current?: current?} = node, definition) do
    %Node{
      name: id,
      label: format_name(id),
      status: status,
      deadline: Map.get(node, :deadline),
      recovery: Map.get(node, :recovery) || definition_recovery(definition, id),
      current?: current?,
      terminal?: terminal_node?(id, status)
    }
  end

  defp graph_edge(%{from: from, to: to, outcome: outcome, recovery: recovery}) do
    %Edge{from: from, to: to, outcome: outcome, recovery: recovery}
  end

  defp terminal_node?(id, status) do
    id == "complete" or status in [:completed, :failed, :cancelled]
  end

  defp format_name(step_name) do
    step_name
    |> to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp definition_recovery({:ok, definition}, step_id) do
    with step_name when is_atom(step_name) <- definition_step_name(definition, step_id),
         {:ok, callback} when not is_nil(callback) <-
           Definition.step_compensation_callback(definition, step_name) do
      %{compensation: %{callback: callback, status: :available}}
    else
      _no_compensation -> nil
    end
  end

  defp definition_recovery(_definition, _step_id), do: nil

  defp definition_step_name(definition, step_id) do
    step_key = to_string(step_id)

    Enum.find_value(definition.steps, nil, fn %{name: step_name} ->
      if to_string(step_name) == step_key, do: step_name
    end)
  end
end
