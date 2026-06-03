defmodule SquidSonarExample.JournalRun do
  @moduledoc """
  Small host-owned worker loop that drains Squidie journal attempts.

  The example app uses Squidie's pull-based journal runtime. This worker gives
  the preview server an execution surface so controls such as approval and resume
  visibly advance scheduled workflow work.
  """

  use GenServer

  require Logger

  @idle_interval_ms 100
  @error_interval_ms 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    state = %{
      owner_id: Keyword.get(opts, :owner_id, "squid-sonar-example-journal-run"),
      idle_interval_ms: Keyword.get(opts, :idle_interval_ms, @idle_interval_ms),
      error_interval_ms: Keyword.get(opts, :error_interval_ms, @error_interval_ms)
    }

    {:ok, state, {:continue, :drain}}
  end

  @impl GenServer
  def handle_continue(:drain, state) do
    {:noreply, drain_once(state)}
  end

  @impl GenServer
  def handle_info(:drain, state) do
    {:noreply, drain_once(state)}
  end

  defp drain_once(state) do
    case Squidie.execute_next(owner_id: state.owner_id) do
      {:ok, :none} ->
        schedule_drain(state.idle_interval_ms)

      {:ok, _snapshot} ->
        schedule_drain(0)

      {:error, reason} ->
        Logger.warning("Squid Sonar example journal drain failed",
          owner_id: state.owner_id,
          reason: inspect(reason)
        )

        schedule_drain(state.error_interval_ms)
    end

    state
  end

  defp schedule_drain(interval_ms) do
    Process.send_after(self(), :drain, interval_ms)
  end
end
