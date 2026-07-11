defmodule SquidSonar.OperatorQueues do
  @moduledoc """
  Builds operator-facing queues from Squidie's public read models and
  host-approved workflow declarations.
  """

  alias SquidSonar.Runs

  require Logger

  defmodule ManualAction do
    @moduledoc false

    @type t :: %__MODULE__{
            run_id: String.t(),
            workflow: term(),
            queue: String.t(),
            step: term(),
            kind: term(),
            reason: term(),
            status: term(),
            created_at: DateTime.t() | NaiveDateTime.t() | String.t() | nil,
            waiting_since: DateTime.t() | NaiveDateTime.t() | String.t() | nil,
            waiting_duration_seconds: non_neg_integer() | nil,
            last_event_summary: String.t()
          }

    @enforce_keys [:run_id, :workflow, :queue, :last_event_summary]

    defstruct [
      :run_id,
      :workflow,
      :queue,
      :step,
      :kind,
      :reason,
      :status,
      :created_at,
      :waiting_since,
      :waiting_duration_seconds,
      :last_event_summary
    ]
  end

  defmodule Schedule do
    @moduledoc false

    @type t :: %__MODULE__{
            workflow: term(),
            trigger: term(),
            expression: String.t(),
            timezone: String.t(),
            last_observed_run: String.t() | nil,
            next_intended_window: DateTime.t() | String.t() | nil,
            status: :host_owned
          }

    @enforce_keys [:workflow, :trigger, :expression, :timezone]

    defstruct [
      :workflow,
      :trigger,
      :expression,
      :timezone,
      :last_observed_run,
      :next_intended_window,
      status: :host_owned
    ]
  end

  @doc """
  Lists active manual boundaries after applying the host visibility policy.

  A paused listing row is re-inspected before projection so a concurrently
  resolved or terminal run does not remain in the operator queue.
  """
  @spec list_manual_actions(keyword()) :: {:ok, [ManualAction.t()]} | {:error, term()}
  def list_manual_actions(opts \\ []) when is_list(opts) do
    runs_opts = Keyword.take(opts, [:client, :squidie])

    with {:ok, summaries} <- Runs.list_runs([status: :paused], runs_opts) do
      project_manual_actions(summaries, opts)
    end
  end

  @doc """
  Lists cron triggers from host-approved workflow specs.

  Scheduling remains host-owned, so fields that require scheduler integration
  stay unset instead of being inferred from runtime configuration.
  """
  @spec list_schedules(term()) :: [Schedule.t()]
  def list_schedules(runtime_specs) do
    runtime_specs
    |> spec_entries()
    |> Enum.flat_map(&schedules_for_entry/1)
    |> Enum.sort_by(&{format_sort_value(&1.workflow), format_sort_value(&1.trigger)})
  end

  defp project_manual_actions(summaries, opts) do
    result =
      Enum.reduce_while(summaries, {:ok, []}, fn summary, {:ok, actions} ->
        case visible_snapshot(summary.id, opts) do
          {:ok, snapshot} ->
            {:cont, {:ok, maybe_add_manual_action(actions, snapshot, opts)}}

          {:error, :not_found} ->
            {:cont, {:ok, actions}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, actions} -> {:ok, Enum.reverse(actions)}
      {:error, _reason} = error -> error
    end
  end

  defp visible_snapshot(run_id, opts) do
    client =
      Keyword.get(
        opts,
        :client,
        Application.get_env(:squid_sonar, :squidie_client, SquidSonar.SquidieClient)
      )

    squidie_opts = Keyword.get(opts, :squidie, [])
    actor = Keyword.get(opts, :visibility_actor, %{})
    policy = Keyword.get(opts, :visibility_policy, :operator)

    with {:ok, snapshot} <- client.inspect_run(run_id, squidie_opts) do
      Squidie.ReadModel.Visibility.redact(snapshot, actor, policy)
    end
  end

  defp maybe_add_manual_action(
         actions,
         %{terminal?: false, manual_state: manual_state} = snapshot,
         opts
       )
       when is_map(manual_state) do
    [manual_action(snapshot, manual_state, opts) | actions]
  end

  defp maybe_add_manual_action(actions, _snapshot, _opts), do: actions

  defp manual_action(snapshot, manual_state, opts) do
    waiting_since =
      map_value(manual_state, :paused_at) || map_value(manual_state, :requested_at)

    kind = map_value(manual_state, :kind)
    reason = map_value(manual_state, :reason)

    %ManualAction{
      run_id: snapshot.run_id,
      workflow: snapshot.workflow,
      queue: snapshot.queue,
      step: map_value(manual_state, :step),
      kind: kind,
      reason: reason,
      status: map_value(manual_state, :status),
      created_at: Map.get(snapshot, :started_at),
      waiting_since: waiting_since,
      waiting_duration_seconds:
        waiting_duration_seconds(waiting_since, Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)),
      last_event_summary: last_event_summary(kind, reason)
    }
  end

  defp waiting_duration_seconds(%DateTime{} = waiting_since, %DateTime{} = now) do
    max(DateTime.diff(now, waiting_since, :second), 0)
  end

  defp waiting_duration_seconds(%NaiveDateTime{} = waiting_since, %DateTime{} = now) do
    waiting_since
    |> DateTime.from_naive!("Etc/UTC")
    |> waiting_duration_seconds(now)
  end

  defp waiting_duration_seconds(_waiting_since, _now), do: nil

  defp last_event_summary(nil, nil), do: "Waiting for manual input"
  defp last_event_summary(kind, nil), do: "Waiting for #{kind}"
  defp last_event_summary(_kind, reason), do: to_string(reason)

  defp spec_entries(nil), do: []

  defp spec_entries(runtime_spec)
       when is_map_key(runtime_spec, :workflow) or is_map_key(runtime_spec, "workflow"),
       do: [{nil, runtime_spec}]

  defp spec_entries(runtime_specs) when is_map(runtime_specs), do: Map.to_list(runtime_specs)

  defp spec_entries(runtime_specs) when is_list(runtime_specs) do
    if Keyword.keyword?(runtime_specs) do
      runtime_specs
    else
      Enum.map(runtime_specs, &{nil, &1})
    end
  end

  defp spec_entries(runtime_spec), do: [{nil, runtime_spec}]

  defp schedules_for_entry({_key, workflow}) when is_atom(workflow) and not is_nil(workflow) do
    case Squidie.Workflow.to_spec(workflow) do
      {:ok, spec} ->
        schedules_for_spec(spec)

      {:error, reason} ->
        Logger.warning("Unable to load schedules for #{inspect(workflow)}: #{inspect(reason)}")

        []
    end
  end

  defp schedules_for_entry({_key, spec}) when is_map(spec), do: schedules_for_spec(spec)
  defp schedules_for_entry(_entry), do: []

  defp schedules_for_spec(spec) do
    workflow = map_value(spec, :workflow)

    spec
    |> map_value(:triggers, [])
    |> List.wrap()
    |> Enum.flat_map(&schedule_for_trigger(workflow, &1))
  end

  defp schedule_for_trigger(workflow, trigger) when is_map(trigger) do
    config = map_value(trigger, :config, %{})

    if cron_trigger?(trigger) and is_map(config) do
      case {map_value(config, :expression), map_value(config, :timezone)} do
        {expression, timezone} when is_binary(expression) and is_binary(timezone) ->
          [
            %Schedule{
              workflow: workflow,
              trigger: map_value(trigger, :name),
              expression: expression,
              timezone: timezone
            }
          ]

        _missing_schedule ->
          []
      end
    else
      []
    end
  end

  defp schedule_for_trigger(_workflow, _trigger), do: []

  defp cron_trigger?(trigger), do: map_value(trigger, :type) in [:cron, "cron"]

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(_value, _key, default), do: default

  defp format_sort_value(nil), do: ""
  defp format_sort_value(value), do: to_string(value)
end
