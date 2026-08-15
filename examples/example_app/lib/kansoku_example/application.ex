defmodule KansokuExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        KansokuExample.Repo,
        {Task.Supervisor, name: KansokuExample.JizokuTaskSupervisor},
        journal_run_child(),
        {Phoenix.PubSub, name: KansokuExample.PubSub},
        KansokuExampleWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: KansokuExample.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    KansokuExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp journal_run_child do
    default_opts = [enabled: endpoint_server?()]

    case Application.get_env(:kansoku_example, :journal_run, default_opts) do
      opts when is_list(opts) ->
        if Keyword.get(opts, :enabled, true), do: {KansokuExample.JournalRun, opts}

      _other ->
        nil
    end
  end

  defp endpoint_server? do
    :kansoku_example
    |> Application.get_env(KansokuExampleWeb.Endpoint, [])
    |> Keyword.get(:server, false)
  end
end
