defmodule SquidSonarExample.Steps.AwaitProviderCallback do
  @moduledoc false

  use Squidie.Step,
    name: "await_provider_callback",
    description: "Defers once so the example app has a deferred continuation run",
    input_schema: [
      order: [type: :map, required: true]
    ],
    output_schema: [
      order_id: [type: :string, required: true],
      status: [type: :string, required: true]
    ]

  alias Squidie.Step.Context

  @impl true
  def run(%{order: %{id: order_id}}, %Context{} = context) do
    if deferred_runnable?(context.runnable_key) do
      {:ok, %{order_id: order_id, status: "provider_ready"}}
    else
      {:defer, defer_reason(order_id), schedule_in: 300}
    end
  end

  defp deferred_runnable?(runnable_key) when is_binary(runnable_key) do
    String.ends_with?(runnable_key, ":deferred")
  end

  defp deferred_runnable?(_runnable_key), do: false

  defp defer_reason(order_id) do
    %{
      message: :awaiting_provider,
      target: %{step: :await_provider_callback, branch: :provider_callback},
      context: %{decision: :hold, provider_reference: "provider_#{order_id}"}
    }
  end
end
