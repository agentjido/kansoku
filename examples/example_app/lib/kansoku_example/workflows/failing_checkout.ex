defmodule KansokuExample.Workflows.FailingCheckout do
  @moduledoc false

  use Jizoku.Workflow

  workflow do
    trigger :failing_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:load_order, KansokuExample.Steps.LoadOrder, output: :order)
    step(:fail_payment, KansokuExample.Steps.FailPayment, input: [:order])

    transition(:load_order, on: :ok, to: :fail_payment)
    transition(:fail_payment, on: :ok, to: :complete)
  end
end
