defmodule Kansoku.Runs.Continuation do
  @moduledoc "Bounded continuation pages built only from visible public run snapshots."

  alias Jizoku.ReadModel.Inspection.Snapshot
  alias Jizoku.ReadModel.Visibility

  @page_size 10

  @doc "Projects safe lineage identifiers and fixed diagnostic messages."
  @spec project(Snapshot.t()) :: map()
  def project(%Snapshot{} = snapshot) do
    %{
      run_id: snapshot.run_id,
      workflow: snapshot.workflow,
      definition_version: snapshot.definition_version,
      status: snapshot.status,
      predecessor: edge(snapshot.continuation, :continued_from),
      successor: edge(snapshot.continuation, :continued_to),
      warnings: warnings(snapshot)
    }
  end

  @doc "Loads a fixed-size page, applying the host visibility policy to every run."
  @spec page(module(), String.t(), :forward | :backward, keyword()) :: map()
  def page(client, run_id, direction, opts) when direction in [:forward, :backward] do
    result =
      load(client, run_id, direction, opts, %{runs: [], next: nil, warning: nil}, %{})

    %{result | runs: Enum.reverse(result.runs)}
  end

  defp load(client, run_id, direction, opts, page, seen) do
    if Map.has_key?(seen, run_id) do
      %{
        page
        | warning: "Continuation cycle detected. Ask the runtime operator to inspect the chain."
      }
    else
      read_next(client, run_id, direction, opts, page, seen)
    end
  end

  defp read_next(client, run_id, direction, opts, page, seen) do
    with {:ok, %Snapshot{run_id: ^run_id} = snapshot} <-
           client.inspect_run(run_id, Keyword.get(opts, :jizoku, [])),
         {:ok, visible} <-
           Visibility.redact(
             snapshot,
             Keyword.get(opts, :visibility_actor, "kansoku"),
             Keyword.get(opts, :visibility_policy, :auditor)
           ) do
      row = project(visible)
      page = %{page | runs: [row | page.runs]}
      next = Map.get(row, if(direction == :forward, do: :successor, else: :predecessor))
      advance(client, next, direction, opts, page, Map.put(seen, run_id, true))
    else
      _error ->
        %{
          page
          | warning:
              "A linked run is unavailable or access was denied. Ask the runtime operator to check continuation recovery."
        }
    end
  end

  defp advance(_client, nil, _direction, _opts, page, _seen), do: page

  defp advance(client, %{run_id: next}, direction, opts, page, seen) do
    if length(page.runs) == @page_size do
      %{page | next: next}
    else
      load(client, next, direction, opts, page, seen)
    end
  end

  defp edge(continuation, key) do
    case Map.get(continuation || %{}, key) do
      %{run_id: id, continuation_key: key} when is_binary(id) and is_binary(key) ->
        %{run_id: id, continuation_key: key}

      _other ->
        nil
    end
  end

  defp warnings(snapshot) do
    snapshot.anomalies
    |> Enum.flat_map(fn anomaly ->
      case Map.get(anomaly, :reason, Map.get(anomaly, :kind, Map.get(anomaly, :code))) do
        :conflicting_continuation ->
          ["Conflicting continuation identity. Ask the runtime operator to inspect recovery."]

        _other ->
          []
      end
    end)
    |> pending_warning(snapshot)
    |> Enum.uniq()
  end

  defp pending_warning(warnings, snapshot) do
    if edge(snapshot.continuation, :continued_to) && not snapshot.terminal? do
      ["Continuation requested; predecessor terminalization is pending." | warnings]
    else
      warnings
    end
  end
end
