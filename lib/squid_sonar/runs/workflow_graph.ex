defmodule SquidSonar.Runs.WorkflowGraph do
  @moduledoc """
  Workflow graph projection for run detail views.
  """

  alias Squidie.ReadModel.Inspection.Snapshot
  alias Squidie.Runs.GraphInspection
  alias Squidie.Workflow.Definition

  defmodule Node do
    @moduledoc false

    @type t :: %__MODULE__{
            name: atom() | String.t(),
            label: String.t(),
            action: atom() | String.t() | nil,
            status: atom(),
            current?: boolean(),
            terminal?: boolean(),
            deadline: map() | nil,
            recovery: map() | nil,
            dynamic?: boolean(),
            origin: map() | nil,
            metadata: map()
          }

    defstruct [
      :name,
      :label,
      :action,
      :status,
      :deadline,
      :recovery,
      :origin,
      current?: false,
      terminal?: false,
      dynamic?: false,
      metadata: %{}
    ]
  end

  defmodule Edge do
    @moduledoc false

    @type t :: %__MODULE__{
            id: String.t() | nil,
            from: atom() | String.t(),
            to: atom() | String.t(),
            type: atom(),
            status: atom(),
            outcome: atom() | nil,
            recovery: atom() | nil
          }

    defstruct [:id, :from, :to, :type, :status, :outcome, :recovery]
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
      action: Map.get(node, :action),
      status: status,
      deadline: Map.get(node, :deadline),
      recovery: Map.get(node, :recovery) || definition_recovery(definition, id),
      dynamic?: Map.get(node, :dynamic?, false),
      origin: Map.get(node, :origin),
      metadata: Map.get(node, :metadata, %{}),
      current?: current?,
      terminal?: terminal_node?(id, status)
    }
  end

  defp graph_edge(%{from: from, to: to} = edge) do
    %Edge{
      id: Map.get(edge, :id),
      from: from,
      to: to,
      type: Map.get(edge, :type, :transition),
      status: Map.get(edge, :status, :pending),
      outcome: Map.get(edge, :outcome),
      recovery: Map.get(edge, :recovery)
    }
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
         {:ok, callback}
         when is_binary(callback) or
                (is_atom(callback) and not is_nil(callback) and not is_boolean(callback)) <-
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
