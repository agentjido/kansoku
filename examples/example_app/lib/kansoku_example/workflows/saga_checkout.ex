defmodule KansokuExample.Workflows.SagaCheckout do
  @moduledoc false

  use Jizoku.Workflow

  workflow do
    trigger :saga_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:reserve_inventory, KansokuExample.Steps.ReserveInventory,
      compensate: KansokuExample.Steps.ReleaseInventory
    )

    step(:load_order, KansokuExample.Steps.LoadOrder, output: :order)
    step(:fail_payment, KansokuExample.Steps.FailPayment, input: [:order])

    transition(:reserve_inventory, on: :ok, to: :load_order)
    transition(:load_order, on: :ok, to: :fail_payment)
    transition(:fail_payment, on: :ok, to: :complete)
  end
end
