defmodule KansokuExample.Steps.RetryOnce do
  @moduledoc false

  use Jido.Action,
    name: "retry_once",
    description: "Requests a retry so the example app has retrying runs",
    schema: [
      order: [type: :map, required: true]
    ],
    output_schema: [
      order_id: [type: :string, required: true],
      status: [type: :string, required: true]
    ]

  @impl true
  def run(%{order: %{id: order_id}}, _context) do
    {:error, %{code: "retry_later", message: "Retry #{order_id} after a short delay"}}
  end
end
