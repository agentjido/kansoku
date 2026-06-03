defmodule SquidSonar.Runs do
  @moduledoc """
  Read boundary for Squidie workflow runs.

  LiveViews should call this module instead of calling `Squidie` directly.
  That keeps runtime access, error handling, and view shaping in one place.
  """

  alias SquidSonar.Runs.RunDetail
  alias SquidSonar.Runs.RunSummary

  @type option :: {:client, module()} | {:squidie, keyword()}

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

  defp client(opts) do
    Keyword.get(
      opts,
      :client,
      Application.get_env(:squid_sonar, :squidie_client, SquidSonar.SquidieClient)
    )
  end
end
