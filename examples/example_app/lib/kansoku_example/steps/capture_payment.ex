defmodule KansokuExample.Steps.CapturePayment do
  @moduledoc false

  use Jido.Action,
    name: "capture_payment",
    description: "Captures payment for a loaded order",
    schema: [
      order: [type: :map, required: true]
    ],
    output_schema: [
      id: [type: :string, required: true],
      amount_cents: [type: :integer, required: true],
      status: [type: :string, required: true]
    ]

  @impl true
  def run(%{order: %{id: order_id, total_cents: total_cents}}, _context) do
    {:ok,
     %{
       id: "pay_#{order_id}",
       amount_cents: total_cents,
       status: "captured"
     }}
  end
end
