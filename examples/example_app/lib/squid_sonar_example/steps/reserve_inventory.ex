defmodule SquidSonarExample.Steps.ReserveInventory do
  @moduledoc false

  use Squidie.Step,
    name: :reserve_inventory,
    description: "Reserves inventory for a checkout order",
    input_schema: [
      order_id: [type: :string, required: true]
    ],
    output_schema: [
      inventory_reservation: [type: :map, required: true]
    ]

  @impl true
  def run(%{order_id: order_id}, _context) do
    {:ok, %{inventory_reservation: %{order_id: order_id, status: "reserved"}}}
  end
end
