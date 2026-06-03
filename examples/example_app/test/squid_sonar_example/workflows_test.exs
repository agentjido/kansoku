defmodule SquidSonarExample.WorkflowsTest do
  use ExUnit.Case, async: true

  alias Squidie.Workflow.Definition
  alias SquidSonarExample.Steps.CapturePayment
  alias SquidSonarExample.Steps.LoadOrder
  alias SquidSonarExample.Workflows.CompletedCheckout

  test "example workflows load through Squidie definitions" do
    workflows = [
      SquidSonarExample.Workflows.CompletedCheckout,
      SquidSonarExample.Workflows.FailingCheckout,
      SquidSonarExample.Workflows.SagaCheckout,
      SquidSonarExample.Workflows.RetryingCheckout,
      SquidSonarExample.Workflows.PausedCheckout,
      SquidSonarExample.Workflows.ManualReviewCheckout
    ]

    for workflow <- workflows do
      assert {:ok, _definition} = Definition.load(workflow)
    end
  end

  test "mapped order output feeds payment capture input" do
    {:ok, definition} = Definition.load(CompletedCheckout)

    assert {:ok, order} =
             LoadOrder.run(%{order_id: "order_123", customer_id: "cust_123"}, step_context())

    assert {:ok, %{order: ^order}} =
             Definition.apply_output_mapping(definition, :load_order, order)

    assert {:ok, payment} = CapturePayment.run(%{order: order}, step_context())

    assert payment == %{
             id: "pay_order_123",
             amount_cents: 4200,
             status: "captured"
           }
  end

  defp step_context do
    %{
      run_id: "run_123",
      workflow: CompletedCheckout,
      step: :load_order,
      state: %{}
    }
  end
end
