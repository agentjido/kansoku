defmodule SquidSonarExample.Workflows.FailingCheckout do
  @moduledoc false

  use Squidie.Workflow

  workflow do
    trigger :failing_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:load_order, SquidSonarExample.Steps.LoadOrder, output: :order)
    step(:fail_payment, SquidSonarExample.Steps.FailPayment, input: [:order])

    transition(:load_order, on: :ok, to: :fail_payment)
    transition(:fail_payment, on: :ok, to: :complete)
  end
end
