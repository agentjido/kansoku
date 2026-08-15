defmodule KansokuExample.Steps.RecordRejection do
  @moduledoc false

  use Jido.Action,
    name: "record_rejection",
    description: "Records a rejected manual review result",
    schema: [
      order_id: [type: :string, required: true],
      approval: [type: :map, required: true]
    ]

  @impl true
  def run(%{order_id: order_id, approval: approval}, _context) do
    {:ok,
     approval
     |> Map.put(:order_id, order_id)
     |> Map.put(:status, "rejected")}
  end
end
