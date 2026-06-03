defmodule SquidSonar.SquidieClient do
  @moduledoc """
  Client boundary for Squidie public APIs.
  """

  @callback list_runs(keyword(), keyword()) ::
              {:ok, [Squidie.ReadModel.Listing.Summary.t()]} | {:error, term()}
  @callback inspect_run(term(), keyword()) ::
              {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @callback inspect_run_graph(term(), keyword()) ::
              {:ok, Squidie.Runs.GraphInspection.t()} | {:error, term()}
  @callback explain_run(term(), keyword()) ::
              {:ok, Squidie.ReadModel.Explanation.Diagnostic.t()} | {:error, term()}
  @callback cancel(term(), keyword()) ::
              {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @callback resume(term(), map(), keyword()) ::
              {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @callback approve(term(), map(), keyword()) ::
              {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @callback reject(term(), map(), keyword()) ::
              {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @callback replay(term(), keyword()) ::
              {:ok, Squidie.ReadModel.Inspection.Snapshot.t()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def list_runs(filters, opts), do: Squidie.list_runs(filters, opts)

  @impl true
  def inspect_run(run_id, opts), do: Squidie.inspect_run(run_id, opts)

  @impl true
  def inspect_run_graph(run_id, opts), do: Squidie.inspect_run_graph(run_id, opts)

  @impl true
  def explain_run(run_id, opts), do: Squidie.explain_run(run_id, opts)

  @impl true
  def cancel(run_id, opts), do: Squidie.cancel(run_id, opts)

  @impl true
  def resume(run_id, attrs, opts), do: Squidie.resume(run_id, attrs, opts)

  @impl true
  def approve(run_id, attrs, opts), do: Squidie.approve(run_id, attrs, opts)

  @impl true
  def reject(run_id, attrs, opts), do: Squidie.reject(run_id, attrs, opts)

  @impl true
  def replay(run_id, opts), do: Squidie.replay(run_id, opts)
end
