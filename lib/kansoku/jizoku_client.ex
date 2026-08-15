defmodule Kansoku.JizokuClient do
  @moduledoc """
  Client boundary for Jizoku public APIs.
  """

  @doc """
  Lists recent Jizoku runs.
  """
  @callback list_runs(keyword(), keyword()) ::
              {:ok, [Jizoku.ReadModel.Listing.Summary.t()]} | {:error, term()}
  @doc """
  Loads a run inspection snapshot.
  """
  @callback inspect_run(term(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @doc """
  Loads the chronological, redaction-safe timeline for a run.
  """
  @callback inspect_run_timeline(term(), keyword()) ::
              {:ok, Jizoku.ReadModel.Timeline.t()} | {:error, term()}
  @doc """
  Loads graph inspection data for a run.
  """
  @callback inspect_run_graph(term(), keyword()) ::
              {:ok, Jizoku.Runs.GraphInspection.t()} | {:error, term()}
  @doc """
  Loads explanation data for a run.
  """
  @callback explain_run(term(), keyword()) ::
              {:ok, Jizoku.ReadModel.Explanation.Diagnostic.t()} | {:error, term()}
  @doc """
  Requests run cancellation.
  """
  @callback cancel(term(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @doc """
  Resumes a paused run.
  """
  @callback resume(term(), map(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @doc """
  Approves a manual approval run.
  """
  @callback approve(term(), map(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @doc """
  Rejects a manual approval run.
  """
  @callback reject(term(), map(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @doc """
  Starts a replay for a terminal run.
  """
  @callback replay(term(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  @doc """
  Starts a run from a compiled Jizoku workflow module.
  """
  @callback start(module(), map(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}

  @doc """
  Starts a run from a runtime-authored workflow spec.
  """
  @callback start_spec(term(), map(), keyword()) ::
              {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}

  @optional_callbacks inspect_run_timeline: 2

  @doc """
  Lists recent Jizoku runs through the configured runtime.
  """
  @spec list_runs(keyword(), keyword()) ::
          {:ok, [Jizoku.ReadModel.Listing.Summary.t()]} | {:error, term()}
  def list_runs(filters, opts), do: Jizoku.list_runs(filters, opts)

  @doc """
  Loads a run inspection snapshot from Jizoku.
  """
  @spec inspect_run(term(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def inspect_run(run_id, opts), do: Jizoku.inspect_run(run_id, opts)

  @doc """
  Loads a run timeline from Jizoku.
  """
  @spec inspect_run_timeline(term(), keyword()) ::
          {:ok, Jizoku.ReadModel.Timeline.t()} | {:error, term()}
  def inspect_run_timeline(run_id, opts), do: Jizoku.inspect_run_timeline(run_id, opts)

  @doc """
  Loads graph inspection data for a Jizoku run.
  """
  @spec inspect_run_graph(term(), keyword()) ::
          {:ok, Jizoku.Runs.GraphInspection.t()} | {:error, term()}
  def inspect_run_graph(run_id, opts), do: Jizoku.inspect_run_graph(run_id, opts)

  @doc """
  Loads operator-facing explanation data for a run.
  """
  @spec explain_run(term(), keyword()) ::
          {:ok, Jizoku.ReadModel.Explanation.Diagnostic.t()} | {:error, term()}
  def explain_run(run_id, opts), do: Jizoku.explain_run(run_id, opts)

  @doc """
  Requests cancellation for a run through Jizoku.
  """
  @spec cancel(term(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def cancel(run_id, opts), do: Jizoku.cancel(run_id, opts)

  @doc """
  Resumes a paused run with host-provided control attributes.
  """
  @spec resume(term(), map(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def resume(run_id, attrs, opts), do: Jizoku.resume(run_id, attrs, opts)

  @doc """
  Approves a manual approval run with host-provided control attributes.
  """
  @spec approve(term(), map(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def approve(run_id, attrs, opts), do: Jizoku.approve(run_id, attrs, opts)

  @doc """
  Rejects a manual approval run with host-provided control attributes.
  """
  @spec reject(term(), map(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def reject(run_id, attrs, opts), do: Jizoku.reject(run_id, attrs, opts)

  @doc """
  Starts a replay for a terminal run.
  """
  @spec replay(term(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def replay(run_id, opts), do: Jizoku.replay(run_id, opts)

  @doc """
  Starts a run from a compiled Jizoku workflow module.
  """
  @spec start(module(), map(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def start(workflow, payload, opts), do: Jizoku.start(workflow, payload, opts)

  @doc """
  Starts a run from a runtime-authored workflow spec.
  """
  @spec start_spec(term(), map(), keyword()) ::
          {:ok, Jizoku.ReadModel.Inspection.Snapshot.t()} | {:error, term()}
  def start_spec(spec, payload, opts), do: Jizoku.start_spec(spec, payload, opts)
end
