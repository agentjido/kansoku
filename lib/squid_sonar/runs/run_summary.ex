defmodule SquidSonar.Runs.RunSummary do
  @moduledoc """
  Compact run projection for list and dashboard views.
  """

  alias SquidMesh.ReadModel.Listing.Summary

  @type t :: %__MODULE__{
          id: String.t(),
          workflow: String.t() | module() | nil,
          queue: String.t(),
          status: atom() | nil,
          terminal_status: atom() | nil,
          deadline: map() | nil,
          indexed_at: DateTime.t() | NaiveDateTime.t() | nil,
          thread_revision: non_neg_integer() | nil,
          anomalies: [map()]
        }

  defstruct [
    :id,
    :workflow,
    :queue,
    :status,
    :terminal_status,
    :deadline,
    :indexed_at,
    :thread_revision,
    anomalies: []
  ]

  @doc false
  @spec from_summary(Summary.t()) :: t()
  def from_summary(%Summary{} = summary) do
    %__MODULE__{
      id: summary.run_id,
      workflow: summary.workflow,
      queue: summary.queue,
      status: summary.status,
      terminal_status: summary.terminal_status,
      deadline: summary.deadline,
      indexed_at: summary.indexed_at,
      thread_revision: summary.thread_revision,
      anomalies: List.wrap(summary.anomalies)
    }
  end
end
