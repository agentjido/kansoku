defmodule SquidSonarExample.Workflows.PausedCheckout do
  @moduledoc false

  use Squidie.Workflow

  workflow do
    trigger :paused_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:load_order, SquidSonarExample.Steps.LoadOrder, output: :order)
    step(:wait_for_operator, :pause)

    step(:capture_payment, SquidSonarExample.Steps.CapturePayment,
      input: [:order],
      output: :payment
    )

    transition(:load_order, on: :ok, to: :wait_for_operator)
    transition(:wait_for_operator, on: :ok, to: :capture_payment)
    transition(:capture_payment, on: :ok, to: :complete)
  end
end
