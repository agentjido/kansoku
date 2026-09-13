defmodule KansokuExample.Steps.Rollover do
  @moduledoc false

  use Jizoku.Step,
    name: "rollover",
    description: "Continues a recurring workflow twice with fresh run history",
    input_schema: [cycle: [type: :integer, required: true]],
    output_schema: [cycle: [type: :integer, required: true]]

  @impl true
  def run(%{cycle: cycle}, _context) when cycle < 3 do
    {:continue_as_new, %{cycle: cycle + 1}, key: "cycle-#{cycle}", definition: :current}
  end

  def run(%{cycle: cycle}, _context), do: {:ok, %{cycle: cycle}}
end
