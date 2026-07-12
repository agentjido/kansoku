defmodule SquidSonar.Dashboard do
  @moduledoc """
  Builds dashboard-ready runtime snapshots.
  """

  alias SquidSonar.OperatorQueues
  alias SquidSonar.Runs

  @statuses [:completed, :failed, :retrying, :paused, :running]
  @terminal_statuses [:completed, :failed, :cancelled]
  @deadline_statuses [:on_time, :due_soon, :overdue, :escalated]
  @time_windows [:"1h", :"24h", :"7d", :"30d"]
  @manual_states [:waiting, :none]
  @default_limit 250
  @default_page_size 10
  @page_sizes [10, 25, 50]
  @filter_text_limit 128
  @query_text_limit 256
  @minimum_run_prefix_length 3
  @run_id_pattern ~r/\A[A-Za-z0-9_.:-]+\z/

  @default_filters %{
    workflow: "",
    status: :all,
    terminal: :all,
    queue: "",
    window: :all,
    run_id: "",
    manual: :all,
    deadline: :all,
    query: ""
  }

  @type t :: %__MODULE__{
          runs: [SquidSonar.Runs.RunSummary.t()],
          statuses: [atom()],
          terminal_statuses: [atom()],
          status_counts: %{atom() => non_neg_integer()},
          filters: map(),
          workflows: [String.t()],
          queues: [String.t()],
          loaded_count: non_neg_integer(),
          filtered_count: non_neg_integer(),
          page: pos_integer(),
          page_size: pos_integer(),
          page_sizes: [pos_integer()],
          total_pages: pos_integer(),
          load_error: term() | nil,
          loaded_at: DateTime.t()
        }

  defstruct [
    :loaded_at,
    :load_error,
    filters: @default_filters,
    filtered_count: 0,
    loaded_count: 0,
    page: 1,
    page_size: @default_page_size,
    page_sizes: @page_sizes,
    runs: [],
    workflows: [],
    queues: [],
    statuses: @statuses,
    terminal_statuses: @terminal_statuses,
    status_counts: %{},
    total_pages: 1
  ]

  @doc """
  Loads recent runs and returns the dashboard snapshot.
  """
  @spec load(keyword()) :: t()
  def load(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    filters = normalize_filters(Keyword.get(opts, :filters, %{}))
    page_size = normalize_page_size(Keyword.get(opts, :page_size))
    requested_page = normalize_page(Keyword.get(opts, :page))
    loaded_at = Keyword.get_lazy(opts, :loaded_at, &DateTime.utc_now/0)
    runs_opts = Keyword.take(opts, [:client, :squidie, :visibility_actor, :visibility_policy])

    with {:ok, runs} <- Runs.list_runs([limit: limit], runs_opts),
         {:ok, manual_action_ids} <- manual_action_ids(filters.manual, opts, loaded_at) do
      filtered_runs = filter_runs(runs, filters, manual_action_ids, loaded_at)
      total_pages = total_pages(filtered_runs, page_size)
      page = clamp_page(requested_page, total_pages)

      %__MODULE__{
        runs: paginate(filtered_runs, page, page_size),
        workflows: option_values(runs, & &1.workflow, filters.workflow),
        queues: option_values(runs, & &1.queue, filters.queue),
        statuses: @statuses,
        terminal_statuses: @terminal_statuses,
        status_counts: status_counts(runs),
        filters: filters,
        loaded_count: length(runs),
        filtered_count: length(filtered_runs),
        page: page,
        page_size: page_size,
        page_sizes: @page_sizes,
        total_pages: total_pages,
        load_error: nil,
        loaded_at: loaded_at
      }
    else
      {:error, reason} -> error_dashboard(filters, page_size, loaded_at, reason)
    end
  end

  @doc """
  Normalizes untrusted URL parameters into dashboard filter and pagination state.
  """
  @spec normalize_params(term()) :: %{
          filters: map(),
          page: pos_integer(),
          page_size: pos_integer()
        }
  def normalize_params(params) do
    %{
      filters: normalize_filters(params),
      page: normalize_page(filter_value(params, :page)),
      page_size: normalize_page_size(filter_value(params, :page_size))
    }
  end

  @doc """
  Serializes normalized dashboard state into a stable, minimal query parameter list.
  """
  @spec query_params(map(), term(), term()) :: [{String.t(), String.t()}]
  def query_params(filters, page, page_size) do
    filters = normalize_filters(filters)
    page = normalize_page(page)
    page_size = normalize_page_size(page_size)

    []
    |> maybe_query_param("workflow", filters.workflow, "")
    |> maybe_query_param("status", filters.status, :all)
    |> maybe_query_param("terminal", filters.terminal, :all)
    |> maybe_query_param("queue", filters.queue, "")
    |> maybe_query_param("window", filters.window, :all)
    |> maybe_query_param("run_id", filters.run_id, "")
    |> maybe_query_param("manual", filters.manual, :all)
    |> maybe_query_param("deadline", filters.deadline, :all)
    |> maybe_query_param("query", filters.query, "")
    |> maybe_query_param("page", page, 1)
    |> maybe_query_param("page_size", page_size, @default_page_size)
    |> Enum.reverse()
  end

  @doc """
  Resolves a unique run id from the bounded recent-run listing.

  Exact matches win over prefix matches. Ambiguous, invalid, missing, and
  unavailable results are returned without inspecting guessed run ids.
  """
  @spec resolve_run_prefix(term(), keyword()) ::
          {:ok, String.t()}
          | {:error, :invalid_prefix | :not_found | :ambiguous | :unavailable}
  def resolve_run_prefix(prefix, opts \\ []) when is_list(opts) do
    with {:ok, normalized_prefix} <- normalize_resolver_prefix(prefix),
         {:ok, runs} <-
           Runs.list_runs(
             [limit: Keyword.get(opts, :limit, @default_limit)],
             Keyword.take(opts, [:client, :squidie, :visibility_actor, :visibility_policy])
           ) do
      resolve_run_matches(runs, normalized_prefix)
    else
      {:error, :invalid_prefix} = error -> error
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp error_dashboard(filters, page_size, loaded_at, reason) do
    %__MODULE__{
      runs: [],
      workflows: [],
      queues: [],
      statuses: @statuses,
      terminal_statuses: @terminal_statuses,
      status_counts: status_counts([]),
      filters: filters,
      loaded_count: 0,
      filtered_count: 0,
      page: 1,
      page_size: page_size,
      page_sizes: @page_sizes,
      total_pages: 1,
      load_error: reason,
      loaded_at: loaded_at
    }
  end

  defp status_counts(runs) do
    base = Map.new(@statuses, &{&1, 0})

    Enum.reduce(runs, base, fn run, counts ->
      Map.update(counts, run.status, 1, &(&1 + 1))
    end)
  end

  defp normalize_filters(filters) do
    %{
      workflow: normalize_text(filter_value(filters, :workflow), @filter_text_limit),
      status: normalize_status(filter_value(filters, :status)),
      terminal: normalize_terminal(filter_value(filters, :terminal)),
      queue: normalize_text(filter_value(filters, :queue), @filter_text_limit),
      window: normalize_window(filter_value(filters, :window)),
      run_id: normalize_run_id(filter_value(filters, :run_id)),
      manual: normalize_manual(filter_value(filters, :manual)),
      deadline: normalize_deadline(filter_value(filters, :deadline)),
      query: normalize_text(filter_value(filters, :query), @query_text_limit)
    }
  end

  defp filter_value(filters, key) when is_map(filters) do
    Map.get(filters, key) || Map.get(filters, to_string(key))
  end

  defp filter_value(filters, key) when is_list(filters) do
    Enum.find_value(filters, fn
      {filter_key, value} ->
        if filter_key == key or filter_key == to_string(key), do: value

      _filter ->
        nil
    end)
  end

  defp filter_value(_filters, _key), do: nil

  defp normalize_status(status) when status in [nil, "", :all, "all"], do: :all
  defp normalize_status(status), do: find_enum(@statuses, status)

  defp normalize_terminal(terminal) when terminal in [nil, "", :all, "all"], do: :all
  defp normalize_terminal(terminal), do: find_enum(@terminal_statuses, terminal)

  defp normalize_window(window) when window in [nil, "", :all, "all"], do: :all
  defp normalize_window(window), do: find_enum(@time_windows, window)

  defp normalize_manual(manual) when manual in [nil, "", :all, "all"], do: :all
  defp normalize_manual(manual), do: find_enum(@manual_states, manual)

  defp normalize_deadline(deadline) when deadline in [nil, "", :all, "all"], do: :all
  defp normalize_deadline(deadline), do: find_enum(@deadline_statuses, deadline)

  defp normalize_text(value, limit) when is_binary(value) do
    value = String.trim(value)

    if byte_size(value) <= limit do
      value
    else
      ""
    end
  end

  defp normalize_text(_value, _limit), do: ""

  defp normalize_run_id(value) do
    value = normalize_text(value, @filter_text_limit)

    if value == "" or Regex.match?(@run_id_pattern, value) do
      value
    else
      ""
    end
  end

  defp find_enum(values, value) when is_binary(value) or is_atom(value) do
    Enum.find(values, :all, &(to_string(&1) == to_string(value)))
  end

  defp find_enum(_values, _value), do: :all

  defp filter_runs(runs, filters, manual_action_ids, loaded_at) do
    runs
    |> Enum.filter(fn run ->
      workflow_matches?(run, filters.workflow) and status_matches?(run, filters.status) and
        terminal_matches?(run, filters.terminal) and queue_matches?(run, filters.queue) and
        window_matches?(run, filters.window, loaded_at) and
        run_id_matches?(run, filters.run_id) and
        manual_matches?(run, filters.manual, manual_action_ids) and
        deadline_matches?(run, filters.deadline) and query_matches?(run, filters.query)
    end)
    |> Enum.sort_by(&sort_value(&1.indexed_at), {:desc, DateTime})
  end

  defp workflow_matches?(_run, ""), do: true
  defp workflow_matches?(run, workflow), do: filter_string(run.workflow) == workflow

  defp status_matches?(_run, :all), do: true
  defp status_matches?(run, status), do: run.status == status

  defp terminal_matches?(_run, :all), do: true
  defp terminal_matches?(run, terminal), do: run.terminal_status == terminal

  defp queue_matches?(_run, ""), do: true
  defp queue_matches?(run, queue), do: filter_string(run.queue) == queue

  defp window_matches?(_run, :all, _loaded_at), do: true

  defp window_matches?(run, window, %DateTime{} = loaded_at) do
    case datetime_value(run.indexed_at) do
      %DateTime{} = indexed_at ->
        cutoff = DateTime.add(loaded_at, -window_seconds(window), :second)
        DateTime.compare(indexed_at, cutoff) in [:eq, :gt]

      nil ->
        false
    end
  end

  defp window_matches?(_run, _window, _loaded_at), do: false

  defp run_id_matches?(_run, ""), do: true
  defp run_id_matches?(%{id: id}, prefix) when is_binary(id), do: String.starts_with?(id, prefix)
  defp run_id_matches?(_run, _prefix), do: false

  defp manual_matches?(_run, :all, _manual_action_ids), do: true
  defp manual_matches?(run, :waiting, ids), do: Map.has_key?(ids, run.id)
  defp manual_matches?(run, :none, ids), do: not Map.has_key?(ids, run.id)

  defp deadline_matches?(_run, :all), do: true

  defp deadline_matches?(run, deadline) do
    run.deadline
    |> map_value(:status)
    |> normalize_deadline()
    |> Kernel.==(deadline)
  end

  defp query_matches?(_run, ""), do: true

  defp query_matches?(run, query) do
    run
    |> searchable_text()
    |> String.contains?(String.downcase(query))
  end

  defp searchable_text(run) do
    [
      run.id,
      run.workflow,
      run.queue,
      run.status,
      run.terminal_status,
      map_value(run.deadline, :status)
    ]
    |> Enum.map_join(" ", &format_search_value/1)
    |> String.downcase()
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp map_value(_value, _key), do: nil

  defp format_search_value(nil), do: ""

  defp format_search_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp format_search_value(value), do: to_string(value)

  defp filter_string(nil), do: ""
  defp filter_string(value), do: to_string(value)

  defp distinct_values(runs, accessor) do
    runs
    |> Enum.map(accessor)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&filter_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp option_values(runs, accessor, selected) do
    values = distinct_values(runs, accessor)

    if selected == "" or selected in values do
      values
    else
      Enum.sort([selected | values])
    end
  end

  defp sort_value(nil), do: ~U[0001-01-01 00:00:00Z]
  defp sort_value(%DateTime{} = datetime), do: datetime
  defp sort_value(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
  defp sort_value(_value), do: ~U[0001-01-01 00:00:00Z]

  defp datetime_value(%DateTime{} = datetime), do: datetime
  defp datetime_value(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
  defp datetime_value(_value), do: nil

  defp window_seconds(:"1h"), do: 60 * 60
  defp window_seconds(:"24h"), do: 24 * 60 * 60
  defp window_seconds(:"7d"), do: 7 * 24 * 60 * 60
  defp window_seconds(:"30d"), do: 30 * 24 * 60 * 60

  defp normalize_page_size(page_size) do
    page_size = parse_positive_integer(page_size, @default_page_size)

    if page_size in @page_sizes do
      page_size
    else
      @default_page_size
    end
  end

  defp normalize_page(page), do: parse_positive_integer(page, 1)

  defp parse_positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> fallback
    end
  end

  defp parse_positive_integer(_value, fallback), do: fallback

  defp total_pages([], _page_size), do: 1

  defp total_pages(runs, page_size) do
    runs
    |> length()
    |> Kernel./(page_size)
    |> Float.ceil()
    |> trunc()
  end

  defp clamp_page(page, total_pages), do: min(page, total_pages)

  defp paginate(runs, page, page_size) do
    offset = (page - 1) * page_size
    Enum.slice(runs, offset, page_size)
  end

  defp manual_action_ids(:all, _opts, _loaded_at), do: {:ok, %{}}

  defp manual_action_ids(_manual, opts, loaded_at) do
    manual_opts =
      opts
      |> Keyword.take([:client, :squidie, :visibility_actor, :visibility_policy])
      |> Keyword.put(:now, loaded_at)

    case OperatorQueues.list_manual_actions(manual_opts) do
      {:ok, actions} -> {:ok, Map.new(actions, &{&1.run_id, true})}
      {:error, _reason} -> {:error, :manual_actions_unavailable}
    end
  end

  defp maybe_query_param(params, _key, value, value), do: params

  defp maybe_query_param(params, key, value, _default) do
    [{key, to_string(value)} | params]
  end

  defp normalize_resolver_prefix(prefix) do
    prefix = normalize_run_id(prefix)

    if byte_size(prefix) >= @minimum_run_prefix_length do
      {:ok, prefix}
    else
      {:error, :invalid_prefix}
    end
  end

  defp resolve_run_matches(runs, prefix) do
    ids =
      runs
      |> Enum.map(& &1.id)
      |> Enum.filter(&is_binary/1)

    if prefix in ids do
      {:ok, prefix}
    else
      case Enum.filter(ids, &String.starts_with?(&1, prefix)) do
        [id] -> {:ok, id}
        [] -> {:error, :not_found}
        _matches -> {:error, :ambiguous}
      end
    end
  end
end
