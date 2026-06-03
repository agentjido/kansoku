defmodule SquidSonarExample.Steps.ReleaseInventory do
  @moduledoc false

  use Squidie.Step,
    name: :release_inventory,
    description: "Releases inventory reserved by the saga checkout example",
    input_schema: [
      step: [type: :map, required: true]
    ],
    output_schema: [
      released_inventory: [type: :map, required: true]
    ]

  @impl true
  def run(%{step: %{output: %{inventory_reservation: reservation}}}, _context) do
    {:ok, %{released_inventory: Map.put(reservation, :status, "released")}}
  end
end
