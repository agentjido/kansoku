defmodule SquidSonarExample.Workflows.SagaCheckout do
  @moduledoc false

  use Squidie.Workflow

  workflow do
    trigger :saga_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:reserve_inventory, SquidSonarExample.Steps.ReserveInventory,
      compensate: SquidSonarExample.Steps.ReleaseInventory
    )

    step(:load_order, SquidSonarExample.Steps.LoadOrder, output: :order)
    step(:fail_payment, SquidSonarExample.Steps.FailPayment, input: [:order])

    transition(:reserve_inventory, on: :ok, to: :load_order)
    transition(:load_order, on: :ok, to: :fail_payment)
    transition(:fail_payment, on: :ok, to: :complete)
  end
end
