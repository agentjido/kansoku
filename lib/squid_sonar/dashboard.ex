defmodule SquidSonar.Dashboard do
  @moduledoc """
  Builds dashboard-ready runtime snapshots.
  """

  alias SquidSonar.Runs

  @statuses [:completed, :failed, :retrying, :paused, :running]
  @deadline_statuses [:on_time, :due_soon, :overdue, :escalated]
  @default_limit 250
  @default_page_size 10
  @page_sizes [10, 25, 50]

  @type t :: %__MODULE__{
          runs: [SquidSonar.Runs.RunSummary.t()],
          statuses: [atom()],
          status_counts: %{atom() => non_neg_integer()},
          filters: map(),
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
    filters: %{status: :all, deadline: :all, query: ""},
    filtered_count: 0,
    loaded_count: 0,
    page: 1,
    page_size: @default_page_size,
    page_sizes: @page_sizes,
    runs: [],
    statuses: @statuses,
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
    runs_opts = Keyword.take(opts, [:client, :squid_mesh])

    case Runs.list_runs([limit: limit], runs_opts) do
      {:ok, runs} ->
        filtered_runs = filter_runs(runs, filters)
        total_pages = total_pages(filtered_runs, page_size)
        page = clamp_page(requested_page, total_pages)

        %__MODULE__{
          runs: paginate(filtered_runs, page, page_size),
          statuses: @statuses,
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

      {:error, reason} ->
        %__MODULE__{
          runs: [],
          statuses: @statuses,
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
  end

  defp status_counts(runs) do
    base = Map.new(@statuses, &{&1, 0})

    Enum.reduce(runs, base, fn run, counts ->
      Map.update(counts, run.status, 1, &(&1 + 1))
    end)
  end

  defp normalize_filters(filters) do
    %{
      status: normalize_status(filter_value(filters, :status)),
      deadline: normalize_deadline(filter_value(filters, :deadline)),
      query: normalize_query(filter_value(filters, :query))
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

  defp normalize_status(status) do
    Enum.find(@statuses, :all, &(to_string(&1) == to_string(status)))
  end

  defp normalize_deadline(deadline) when deadline in [nil, "", :all, "all"], do: :all

  defp normalize_deadline(deadline) do
    Enum.find(@deadline_statuses, :all, &(to_string(&1) == to_string(deadline)))
  end

  defp normalize_query(nil), do: ""

  defp normalize_query(query) do
    query
    |> to_string()
    |> String.trim()
  end

  defp filter_runs(runs, filters) do
    runs
    |> Enum.filter(fn run ->
      status_matches?(run, filters.status) and deadline_matches?(run, filters.deadline) and
        query_matches?(run, filters.query)
    end)
    |> Enum.sort_by(&sort_value(&1.indexed_at), {:desc, DateTime})
  end

  defp status_matches?(_run, :all), do: true
  defp status_matches?(run, status), do: run.status == status

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
    |> Enum.map(&format_search_value/1)
    |> Enum.join(" ")
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

  defp sort_value(nil), do: ~U[0001-01-01 00:00:00Z]
  defp sort_value(%DateTime{} = datetime), do: datetime
  defp sort_value(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
  defp sort_value(_value), do: ~U[0001-01-01 00:00:00Z]

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
end
