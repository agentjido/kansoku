defmodule SquidSonarExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SquidSonarExample.Repo,
        {Task.Supervisor, name: SquidSonarExample.SquidieTaskSupervisor},
        journal_run_child(),
        {Phoenix.PubSub, name: SquidSonarExample.PubSub},
        SquidSonarExampleWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: SquidSonarExample.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SquidSonarExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp journal_run_child do
    default_opts = [enabled: endpoint_server?()]

    case Application.get_env(:squid_sonar_example, :journal_run, default_opts) do
      opts when is_list(opts) ->
        if Keyword.get(opts, :enabled, true), do: {SquidSonarExample.JournalRun, opts}

      _other ->
        nil
    end
  end

  defp endpoint_server? do
    :squid_sonar_example
    |> Application.get_env(SquidSonarExampleWeb.Endpoint, [])
    |> Keyword.get(:server, false)
  end
end
