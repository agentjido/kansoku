defmodule SquidSonarExample.Workflows.ManualReviewCheckout do
  @moduledoc false

  use Squidie.Workflow

  workflow do
    trigger :manual_review_checkout do
      manual()

      payload do
        field(:order_id, :string)
        field(:customer_id, :string)
      end
    end

    approval_step(:wait_for_review, output: :approval)

    step(:record_approval, SquidSonarExample.Steps.RecordApproval,
      input: [:order_id, :approval],
      output: :approval
    )

    step(:record_rejection, SquidSonarExample.Steps.RecordRejection,
      input: [:order_id, :approval],
      output: :approval
    )

    transition(:wait_for_review, on: :ok, to: :record_approval)
    transition(:wait_for_review, on: :error, to: :record_rejection)
    transition(:record_approval, on: :ok, to: :complete)
    transition(:record_rejection, on: :ok, to: :complete)
  end
end
