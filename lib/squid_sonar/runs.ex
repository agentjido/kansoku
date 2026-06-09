defmodule SquidSonar.Runs do
  @moduledoc """
  Read boundary for Squidie workflow runs.

  LiveViews should call this module instead of calling `Squidie` directly.
  That keeps runtime access, error handling, and view shaping in one place.
  """

  alias SquidSonar.Runs.RunDetail
  alias SquidSonar.Runs.RunSummary

  @type option :: {:client, module()} | {:squidie, keyword()} | {:action_registry, term()}

  @doc """
  Lists recent runs as UI-friendly summaries.
  """
  @spec list_runs(keyword(), [option()]) ::
          {:ok, [RunSummary.t()]} | {:error, term()}
  def list_runs(filters \\ [], opts \\ []) when is_list(filters) and is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])

    with {:ok, runs} <- client.list_runs(filters, squidie_opts) do
      {:ok, Enum.map(runs, &RunSummary.from_summary/1)}
    end
  end

  @doc """
  Fetches one run with runtime snapshot, graph projection, and diagnostic explanation.
  """
  @spec get_run(term(), [option()]) :: {:ok, RunDetail.t()} | {:error, term()}
  def get_run(run_id, opts \\ []) when is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])

    with {:ok, snapshot} <- client.inspect_run(run_id, squidie_opts),
         {:ok, graph} <- client.inspect_run_graph(run_id, squidie_opts),
         {:ok, explanation} <- client.explain_run(run_id, squidie_opts) do
      {:ok, RunDetail.from_models(snapshot, explanation, graph)}
    end
  end

  @doc """
  Cancels an eligible workflow run.
  """
  @spec cancel_run(term(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def cancel_run(run_id, opts \\ []) when is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])
    client.cancel(run_id, squidie_opts)
  end

  @doc """
  Resumes a paused workflow run.
  """
  @spec resume_run(term(), map(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def resume_run(run_id, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])
    client.resume(run_id, attrs, squidie_opts)
  end

  @doc """
  Approves a paused approval step and resumes through success path.
  """
  @spec approve_run(term(), map(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def approve_run(run_id, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])
    client.approve(run_id, attrs, squidie_opts)
  end

  @doc """
  Rejects a paused approval step and resumes through rejection path.
  """
  @spec reject_run(term(), map(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def reject_run(run_id, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])
    client.reject(run_id, attrs, squidie_opts)
  end

  @doc """
  Replays a completed or failed workflow run.
  """
  @spec replay_run(term(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def replay_run(run_id, opts \\ []) when is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])
    client.replay(run_id, squidie_opts)
  end

  @doc """
  Starts a run from a host-provided runtime workflow spec.
  """
  @spec start_spec(term(), map(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def start_spec(spec, payload, opts \\ []) when is_list(opts) do
    client = client(opts)

    squidie_opts =
      opts
      |> Keyword.get(:squidie, [])
      |> put_action_registry(Keyword.get(opts, :action_registry))

    client.start_spec(spec, normalize_spec_payload(spec, payload), squidie_opts)
  end

  @doc """
  Starts a run from a host-provided Squidie workflow module.
  """
  @spec start_workflow(module(), map(), [option()]) ::
          {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def start_workflow(workflow, payload, opts \\ []) when is_atom(workflow) and is_list(opts) do
    client = client(opts)
    squidie_opts = Keyword.get(opts, :squidie, [])

    client.start(workflow, normalize_workflow_payload(workflow, payload), squidie_opts)
  end

  defp client(opts) do
    Keyword.get(
      opts,
      :client,
      Application.get_env(:squid_sonar, :squidie_client, SquidSonar.SquidieClient)
    )
  end

  defp put_action_registry(opts, nil), do: opts

  defp put_action_registry(opts, action_registry) do
    opts
    |> Keyword.delete(:action_registry)
    |> Kernel.++(action_registry: action_registry)
  end

  defp normalize_spec_payload(spec, payload) when is_map(payload) do
    spec
    |> spec_payload_fields()
    |> Enum.reduce(payload, &normalize_payload_field/2)
  end

  defp normalize_spec_payload(_spec, payload), do: payload

  defp normalize_workflow_payload(workflow, payload) when is_map(payload) do
    case Squidie.Workflow.to_spec(workflow) do
      {:ok, spec} -> normalize_spec_payload(spec, payload)
      {:error, _reason} -> payload
    end
  end

  defp normalize_workflow_payload(_workflow, payload), do: payload

  defp spec_payload_fields(%{payload: payload}) when is_list(payload), do: payload
  defp spec_payload_fields(%{"payload" => payload}) when is_list(payload), do: payload
  defp spec_payload_fields(_spec), do: []

  defp normalize_payload_field(field, payload) when is_map(field) do
    field
    |> payload_field_name()
    |> normalize_payload_field_name(payload)
  end

  defp normalize_payload_field(_field, payload), do: payload

  defp payload_field_name(%{name: name}), do: name
  defp payload_field_name(%{"name" => name}), do: name
  defp payload_field_name(_field), do: nil

  defp normalize_payload_field_name(name, payload) when is_atom(name) and not is_nil(name) do
    string_name = Atom.to_string(name)

    case Map.fetch(payload, string_name) do
      {:ok, value} ->
        payload
        |> Map.put_new(name, value)
        |> Map.delete(string_name)

      :error ->
        payload
    end
  end

  defp normalize_payload_field_name(_name, payload), do: payload
end
