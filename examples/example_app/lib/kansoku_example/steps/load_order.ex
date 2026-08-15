defmodule KansokuExample.Steps.LoadOrder do
  @moduledoc false

  use Jido.Action,
    name: "load_order",
    description: "Loads order context",
    schema: [
      order_id: [type: :string, required: true],
      customer_id: [type: :string, required: true]
    ],
    output_schema: [
      id: [type: :string, required: true],
      customer_id: [type: :string, required: true],
      total_cents: [type: :integer, required: true]
    ]

  @impl true
  def run(%{order_id: order_id, customer_id: customer_id}, _context) do
    {:ok,
     %{
       id: order_id,
       customer_id: customer_id,
       total_cents: 4200
     }}
  end
end
