defmodule SquidSonarExample.RuntimeSpecDemo do
  @moduledoc false

  alias SquidSonarExample.Steps.CapturePayment
  alias SquidSonarExample.Steps.LoadOrder
  alias SquidSonarExample.Workflows.CompletedCheckout
  alias SquidSonarExample.Workflows.DeferredCheckout
  alias SquidSonarExample.Workflows.FailingCheckout
  alias SquidSonarExample.Workflows.InvoiceReconciliation
  alias SquidSonarExample.Workflows.ManualReviewCheckout
  alias SquidSonarExample.Workflows.PausedCheckout
  alias SquidSonarExample.Workflows.RetryingCheckout
  alias SquidSonarExample.Workflows.SagaCheckout
  alias Squidie.Workflow.EditorSpec

  @spec runtime_specs(Plug.Conn.t()) :: keyword(module())
  def runtime_specs(_conn) do
    [
      completed_checkout: CompletedCheckout,
      invoice_reconciliation: InvoiceReconciliation,
      retrying_checkout: RetryingCheckout,
      paused_checkout: PausedCheckout,
      manual_review_checkout: ManualReviewCheckout,
      deferred_checkout: DeferredCheckout,
      failing_checkout: FailingCheckout,
      saga_checkout: SagaCheckout
    ]
  end

  @spec spec(Plug.Conn.t()) :: map()
  def spec(_conn) do
    payload = payload_contract()

    %{
      workflow: CompletedCheckout,
      triggers: [
        %{
          name: :runtime_checkout,
          type: :manual,
          config: %{},
          payload: payload
        }
      ],
      payload: payload,
      steps: [
        %{
          name: :load_order,
          action: "load_order",
          opts: [output: :order]
        },
        %{
          name: :capture_payment,
          action: "capture_payment",
          opts: [input: [:order], output: :payment]
        }
      ],
      transitions: [
        %{from: :load_order, on: :ok, to: :capture_payment},
        %{from: :capture_payment, on: :ok, to: :complete}
      ],
      retries: [],
      entry_steps: [:load_order],
      initial_step: :load_order,
      entry_step: :load_order
    }
  end

  @spec saved_specs(Plug.Conn.t()) :: keyword(map())
  def saved_specs(conn) do
    runtime_spec = spec(conn)

    [
      checkout_runtime_spec: %{
        title: "Runtime checkout spec",
        description: "Approved runtime-authored checkout spec owned by the host app.",
        status: :approved,
        editor_json: EditorSpec.to_map(runtime_spec),
        source_spec: EditorSpec.to_map(source_spec(conn)),
        spec: runtime_spec
      }
    ]
  end

  @spec action_registry(Plug.Conn.t()) :: map()
  def action_registry(_conn) do
    %{
      "load_order" => LoadOrder,
      "capture_payment" => CapturePayment
    }
  end

  defp payload_contract do
    [
      %{name: :order_id, type: :string, opts: []},
      %{name: :customer_id, type: :string, opts: []}
    ]
  end

  defp source_spec(conn) do
    runtime_spec = spec(conn)

    %{
      runtime_spec
      | steps: [
          %{
            name: :load_order,
            action: "load_order",
            opts: [output: :order]
          }
        ],
        transitions: [%{from: :load_order, on: :ok, to: :complete}]
    }
  end
end
