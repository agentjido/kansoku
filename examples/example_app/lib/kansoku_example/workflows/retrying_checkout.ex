defmodule KansokuExample.Workflows.RetryingCheckout do
  @moduledoc false

  use Jizoku.Workflow

  workflow do
    trigger :retrying_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    step(:load_order, KansokuExample.Steps.LoadOrder, output: :order)

    step(:retry_once, KansokuExample.Steps.RetryOnce,
      input: [:order],
      output: :retry_probe,
      retry: [max_attempts: 3, backoff: [type: :exponential, min: 2_000, max: 2_000]]
    )

    transition(:load_order, on: :ok, to: :retry_once)
    transition(:retry_once, on: :ok, to: :complete)
  end
end
