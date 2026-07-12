defmodule SquidSonar.FakeSquidieClient do
  @moduledoc false

  @behaviour SquidSonar.SquidieClient

  @impl SquidSonar.SquidieClient
  def list_runs(filters, opts) do
    result({__MODULE__, :list_runs}, [filters, opts], {:ok, []})
  end

  @impl SquidSonar.SquidieClient
  def inspect_run(run_id, opts) do
    result({__MODULE__, :inspect_run}, [run_id, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def inspect_run_timeline(run_id, opts) do
    result({__MODULE__, :inspect_run_timeline}, [run_id, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def inspect_run_graph(run_id, opts) do
    result({__MODULE__, :inspect_run_graph}, [run_id, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def explain_run(run_id, opts) do
    result({__MODULE__, :explain_run}, [run_id, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def cancel(run_id, opts) do
    result({__MODULE__, :cancel}, [run_id, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def resume(run_id, attrs, opts) do
    result({__MODULE__, :resume}, [run_id, attrs, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def approve(run_id, attrs, opts) do
    result({__MODULE__, :approve}, [run_id, attrs, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def reject(run_id, attrs, opts) do
    result({__MODULE__, :reject}, [run_id, attrs, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def replay(run_id, opts) do
    result({__MODULE__, :replay}, [run_id, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def start(workflow, payload, opts) do
    result({__MODULE__, :start}, [workflow, payload, opts], {:error, :not_found})
  end

  @impl SquidSonar.SquidieClient
  def start_spec(spec, payload, opts) do
    result({__MODULE__, :start_spec}, [spec, payload, opts], {:error, :not_found})
  end

  @doc """
  Sets the fake response for listing runs.
  """
  @spec put_list_runs(term()) :: term()
  def put_list_runs(result), do: Process.put({__MODULE__, :list_runs}, result)

  @doc """
  Sets the fake response for run inspection.
  """
  @spec put_inspect_run(term()) :: term()
  def put_inspect_run(result), do: Process.put({__MODULE__, :inspect_run}, result)

  @doc """
  Sets the fake response for run timeline inspection.
  """
  @spec put_inspect_run_timeline(term()) :: term()
  def put_inspect_run_timeline(result),
    do: Process.put({__MODULE__, :inspect_run_timeline}, result)

  @doc """
  Sets the fake response for graph inspection.
  """
  @spec put_inspect_run_graph(term()) :: term()
  def put_inspect_run_graph(result), do: Process.put({__MODULE__, :inspect_run_graph}, result)

  @doc """
  Sets the fake response for run explanation.
  """
  @spec put_explain_run(term()) :: term()
  def put_explain_run(result), do: Process.put({__MODULE__, :explain_run}, result)

  @doc """
  Sets the fake response for cancellation.
  """
  @spec put_cancel(term()) :: term()
  def put_cancel(result), do: Process.put({__MODULE__, :cancel}, result)

  @doc """
  Sets the fake response for pause resume.
  """
  @spec put_resume(term()) :: term()
  def put_resume(result), do: Process.put({__MODULE__, :resume}, result)

  @doc """
  Sets the fake response for approval.
  """
  @spec put_approve(term()) :: term()
  def put_approve(result), do: Process.put({__MODULE__, :approve}, result)

  @doc """
  Sets the fake response for rejection.
  """
  @spec put_reject(term()) :: term()
  def put_reject(result), do: Process.put({__MODULE__, :reject}, result)

  @doc """
  Sets the fake response for replay.
  """
  @spec put_replay(term()) :: term()
  def put_replay(result), do: Process.put({__MODULE__, :replay}, result)

  @doc """
  Sets the fake response for workflow starts.
  """
  @spec put_start(term()) :: term()
  def put_start(result), do: Process.put({__MODULE__, :start}, result)

  @doc """
  Sets the fake response for runtime spec starts.
  """
  @spec put_start_spec(term()) :: term()
  def put_start_spec(result), do: Process.put({__MODULE__, :start_spec}, result)

  defp result(key, args, default) do
    case Process.get(key, default) do
      fun when is_function(fun) -> apply(fun, args)
      result -> result
    end
  end
end
