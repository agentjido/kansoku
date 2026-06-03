defmodule SquidSonar.FakeSquidieClient do
  @moduledoc false

  @behaviour SquidSonar.SquidieClient

  @impl true
  def list_runs(filters, opts) do
    result({__MODULE__, :list_runs}, [filters, opts], {:ok, []})
  end

  @impl true
  def inspect_run(run_id, opts) do
    result({__MODULE__, :inspect_run}, [run_id, opts], {:error, :not_found})
  end

  @impl true
  def inspect_run_graph(run_id, opts) do
    result({__MODULE__, :inspect_run_graph}, [run_id, opts], {:error, :not_found})
  end

  @impl true
  def explain_run(run_id, opts) do
    result({__MODULE__, :explain_run}, [run_id, opts], {:error, :not_found})
  end

  @impl true
  def cancel(run_id, opts) do
    result({__MODULE__, :cancel}, [run_id, opts], {:error, :not_found})
  end

  @impl true
  def resume(run_id, attrs, opts) do
    result({__MODULE__, :resume}, [run_id, attrs, opts], {:error, :not_found})
  end

  @impl true
  def approve(run_id, attrs, opts) do
    result({__MODULE__, :approve}, [run_id, attrs, opts], {:error, :not_found})
  end

  @impl true
  def reject(run_id, attrs, opts) do
    result({__MODULE__, :reject}, [run_id, attrs, opts], {:error, :not_found})
  end

  @impl true
  def replay(run_id, opts) do
    result({__MODULE__, :replay}, [run_id, opts], {:error, :not_found})
  end

  def put_list_runs(result), do: Process.put({__MODULE__, :list_runs}, result)
  def put_inspect_run(result), do: Process.put({__MODULE__, :inspect_run}, result)
  def put_inspect_run_graph(result), do: Process.put({__MODULE__, :inspect_run_graph}, result)
  def put_explain_run(result), do: Process.put({__MODULE__, :explain_run}, result)
  def put_cancel(result), do: Process.put({__MODULE__, :cancel}, result)
  def put_resume(result), do: Process.put({__MODULE__, :resume}, result)
  def put_approve(result), do: Process.put({__MODULE__, :approve}, result)
  def put_reject(result), do: Process.put({__MODULE__, :reject}, result)
  def put_replay(result), do: Process.put({__MODULE__, :replay}, result)

  defp result(key, args, default) do
    case Process.get(key, default) do
      fun when is_function(fun, length(args)) -> apply(fun, args)
      result -> result
    end
  end
end
