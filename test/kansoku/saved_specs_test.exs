defmodule Kansoku.SavedSpecsTest do
  use ExUnit.Case, async: true

  alias Kansoku.SavedSpecs

  test "gets one saved spec by host key" do
    saved_specs = [
      first_spec: %{title: "First spec", editor_json: editor_json("FirstWorkflow")},
      checkout_runtime_spec: %{title: "Checkout runtime spec", editor_json: editor_json()}
    ]

    assert {:ok, saved_spec} = SavedSpecs.get(saved_specs, "checkout_runtime_spec")
    assert saved_spec.key == "checkout_runtime_spec"
    assert saved_spec.title == "Checkout runtime spec"
  end

  test "returns not found for missing host key" do
    assert SavedSpecs.get([checkout_runtime_spec: %{editor_json: editor_json()}], "missing") ==
             {:error, :not_found}
  end

  test "returns not found when the matching saved spec cannot be built" do
    assert SavedSpecs.get([checkout_runtime_spec: nil], "checkout_runtime_spec") ==
             {:error, :not_found}
  end

  defp editor_json(workflow \\ "RuntimeCheckout") do
    %{
      "workflow" => workflow,
      "triggers" => [%{"name" => "manual", "type" => "manual", "config" => %{}, "payload" => []}],
      "payload" => [%{"name" => "order_id", "type" => "string", "opts" => []}],
      "steps" => [%{"name" => "load_order", "action" => "load_order", "opts" => %{}}],
      "transitions" => [%{"from" => "load_order", "on" => "ok", "to" => "complete"}],
      "retries" => [],
      "entry_steps" => ["load_order"],
      "initial_step" => "load_order",
      "entry_step" => "load_order"
    }
  end
end
