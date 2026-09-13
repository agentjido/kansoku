defmodule KansokuWeb.ContinuationComponents do
  @moduledoc "Continuation lineage and bounded chain navigation."

  use Phoenix.Component

  attr :continuation, :map, required: true
  attr :page, :any, default: nil
  attr :prefix, :string, required: true

  @doc "Displays visible continuation links and one page of the chain."
  @spec continuation_card(map()) :: Phoenix.LiveView.Rendered.t()
  def continuation_card(assigns) do
    ~H"""
    <section
      :if={@continuation.predecessor || @continuation.successor || @continuation.warnings != []}
      id="continuation-card"
      class="kansoku-detail-panel kansoku-continuation-card"
      aria-label="Continuation chain"
    >
      <h2>Continuation chain</h2>
      <p>
        Workflow: {@continuation.workflow} · Definition: {@continuation.definition_version ||
          "Not available"}
      </p>
      <p :for={warning <- @continuation.warnings} role="status">{warning}</p>
      <p :for={
        {label, edge} <- [
          {"Predecessor", @continuation.predecessor},
          {"Successor", @continuation.successor}
        ]
      }>
        <%= if edge do %>
          {label}:
          <.link navigate={@prefix <> "/runs/" <> URI.encode_www_form(edge.run_id)}>{edge.run_id}</.link>
          · Continuation key: {edge.continuation_key}
        <% else %>
          {label}: None recorded
        <% end %>
      </p>
      <div class="kansoku-control-buttons">
        <button
          :if={@continuation.predecessor}
          class="kansoku-control-button kansoku-control-button-secondary"
          type="button"
          phx-click="continuation_backward"
        >Earlier runs</button>
        <button
          :if={@continuation.successor}
          class="kansoku-control-button kansoku-control-button-secondary"
          type="button"
          phx-click="continuation_forward"
        >Later runs</button>
      </div>
      <div :if={@page} id="continuation-page" aria-live="polite">
        <p>Up to ten runs per page. Select a run to inspect it.</p>
        <p :if={@page.warning} role="status">{@page.warning}</p>
        <ol>
          <li :for={run <- @page.runs}>
            <.link navigate={@prefix <> "/runs/" <> URI.encode_www_form(run.run_id)}>{run.run_id}</.link>
            · {run.status} · Definition: {run.definition_version || "Not available"}
            <p :for={warning <- run.warnings} role="status">{warning}</p>
          </li>
        </ol>
        <button
          :if={@page.next}
          id="continuation-next"
          class="kansoku-control-button kansoku-control-button-secondary"
          type="button"
          phx-click="continuation_next"
        >Next ten runs</button>
      </div>
    </section>
    """
  end
end
