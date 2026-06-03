defmodule SquidSonarExample.SquidieExecutor do
  @moduledoc false

  @behaviour Squidie.Executor

  alias Squidie.Executor.Payload
  alias Squidie.Runtime.Runner

  @impl true
  def enqueue_cron(_config, workflow, trigger, opts) do
    workflow
    |> Payload.cron(trigger)
    |> enqueue_payload(opts)
  end

  defp enqueue_payload(payload, opts) do
    schedule_in = Keyword.get(opts, :schedule_in, 0)

    case Task.Supervisor.start_child(SquidSonarExample.SquidieTaskSupervisor, fn ->
           maybe_sleep(schedule_in)
           Runner.perform(payload)
         end) do
      {:ok, pid} ->
        {:ok,
         %{
           adapter: __MODULE__,
           pid: inspect(pid),
           schedule_in: schedule_in
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_sleep(schedule_in) when is_integer(schedule_in) and schedule_in > 0 do
    Process.sleep(:timer.seconds(schedule_in))
  end

  defp maybe_sleep(_schedule_in), do: Process.sleep(25)
end
