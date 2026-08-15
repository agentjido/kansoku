defmodule Kansoku.ReadModelFixturesTest do
  use ExUnit.Case, async: true

  import Kansoku.ReadModelFixtures

  test "builds reusable compensation recovery metadata" do
    assert compensation_recovery("ReleaseInventory") == %{
             compensation: %{callback: "ReleaseInventory", status: :available}
           }

    assert compensation_recovery("ReleaseInventory", status: :blocked) == %{
             compensation: %{callback: "ReleaseInventory", status: :blocked}
           }
  end

  test "builds recovery policy diagnostic evidence" do
    recovery = compensation_recovery("ReleaseInventory")

    assert recovery_policy_evidence("reserve_inventory", recovery) == %{
             recovery_policies: %{"reserve_inventory" => recovery}
           }
  end

  test "builds recovery-aware attempts" do
    recovery = compensation_recovery("ReleaseInventory")

    assert attempt("reserve_inventory", :claimed, 1, nil, recovery: recovery) == %{
             step: "reserve_inventory",
             status: :claimed,
             attempt_number: 1,
             error: nil,
             recovery: recovery
           }
  end
end
