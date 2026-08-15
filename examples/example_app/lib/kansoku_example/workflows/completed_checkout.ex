defmodule KansokuExample.Workflows.CompletedCheckout do
  @moduledoc false

  use Jizoku.Workflow

  workflow do
    trigger :completed_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:load_order, KansokuExample.Steps.LoadOrder, output: :order)

    step(:capture_payment, KansokuExample.Steps.CapturePayment,
      input: [:order],
      output: :payment
    )

    transition(:load_order, on: :ok, to: :capture_payment)
    transition(:capture_payment, on: :ok, to: :complete)
  end
end
