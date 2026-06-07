defmodule SquidSonarExample.WorkflowsTest do
  use ExUnit.Case, async: true

  alias Squidie.Workflow.Definition
  alias Squidie.Step.Context
  alias SquidSonarExample.Steps.AwaitProviderCallback
  alias SquidSonarExample.Steps.CapturePayment
  alias SquidSonarExample.Steps.LoadOrder
  alias SquidSonarExample.Workflows.CompletedCheckout
  alias SquidSonarExample.Workflows.DeferredCheckout

  test "example workflows load through Squidie definitions" do
    workflows = [
      SquidSonarExample.Workflows.CompletedCheckout,
      SquidSonarExample.Workflows.FailingCheckout,
      SquidSonarExample.Workflows.SagaCheckout,
      SquidSonarExample.Workflows.RetryingCheckout,
      SquidSonarExample.Workflows.DeferredCheckout,
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

  test "deferred checkout step waits once and completes on the deferred runnable" do
    input = %{order: %{id: "order_123"}}

    assert {:defer, reason, [schedule_in: 300]} =
             AwaitProviderCallback.run(input, step_context())

    assert reason == %{
             message: :awaiting_provider,
             target: %{step: :await_provider_callback, branch: :provider_callback},
             context: %{decision: :hold, provider_reference: "provider_order_123"}
           }

    resumed_context = %Context{
      step_context()
      | runnable_key: "run_123:await_provider_callback:deferred"
    }

    assert {:ok, %{order_id: "order_123", status: "provider_ready"}} =
             AwaitProviderCallback.run(input, resumed_context)
  end

  defp step_context do
    %Context{
      run_id: "run_123",
      workflow: DeferredCheckout,
      step: :await_provider_callback,
      attempt: 1,
      runnable_key: "run_123:await_provider_callback",
      state: %{}
    }
  end
end
