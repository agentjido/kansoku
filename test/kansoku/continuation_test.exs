defmodule Kansoku.ContinuationTest do
  use ExUnit.Case, async: true

  import Kansoku.ReadModelFixtures

  alias Kansoku.FakeJizokuClient
  alias Kansoku.Runs
  alias Kansoku.Runs.Continuation

  test "pages a long chain without overlap and preserves runtime options" do
    FakeJizokuClient.put_inspect_run(fn id, opts ->
      assert opts == [partition: "tenant-a"]
      send(self(), {:read, id})
      n = String.to_integer(id)
      {:ok, run(id, if(n < 22, do: Integer.to_string(n + 1)))}
    end)

    opts = [
      client: FakeJizokuClient,
      jizoku: [partition: "tenant-a"],
      visibility_policy: :operator
    ]

    first = Runs.continuation_page("1", :forward, opts)
    assert Enum.map(first.runs, & &1.run_id) == Enum.map(1..10, &to_string/1)
    assert first.next == "11"
    refute_received {:read, "11"}
    second = Runs.continuation_page(first.next, :forward, opts)
    assert Enum.map(second.runs, & &1.run_id) == Enum.map(11..20, &to_string/1)
    last = Runs.continuation_page(second.next, :forward, opts)
    assert Enum.map(last.runs, & &1.run_id) == ["21", "22"]
    assert last.next == nil
  end

  test "retains visible rows when a neighbor is missing and hides error details" do
    FakeJizokuClient.put_inspect_run(fn
      "1", _opts -> {:ok, run("1", "2")}
      "2", _opts -> {:error, {:not_found, "secret storage detail"}}
    end)

    page = Runs.continuation_page("1", :forward, client: FakeJizokuClient)
    assert [_row] = page.runs
    assert page.warning =~ "unavailable"
    refute inspect(page) =~ "secret"
  end

  test "detects cycles within the bounded page" do
    FakeJizokuClient.put_inspect_run(fn id, _opts -> {:ok, run(id, id)} end)
    page = Runs.continuation_page("1", :forward, client: FakeJizokuClient)
    assert [_row] = page.runs
    assert page.warning =~ "cycle"
  end

  test "detects a cycle at the page boundary without offering another page" do
    FakeJizokuClient.put_inspect_run(fn id, _opts ->
      n = String.to_integer(id)
      {:ok, run(id, if(n == 10, do: "1", else: to_string(n + 1)))}
    end)

    page = Runs.continuation_page("1", :forward, client: FakeJizokuClient)
    assert Enum.map(page.runs, & &1.run_id) == Enum.map(1..10, &to_string/1)
    assert page.next == nil
    assert page.warning =~ "cycle"
  end

  test "preserves the page anchor when its first run is unavailable" do
    FakeJizokuClient.put_inspect_run({:error, :not_found})
    page = Runs.continuation_page("missing", :forward, client: FakeJizokuClient)
    assert page.run_id == "missing"
    assert page.runs == []
    assert page.next == nil
  end

  test "applies visibility to each run and never returns payload or raw evidence" do
    FakeJizokuClient.put_inspect_run(fn id, _opts -> {:ok, run(id, "2")} end)

    policy = fn actor, snapshot ->
      assert actor == "operator-id"
      if snapshot.run_id == "1", do: :operator, else: {:error, :denied}
    end

    page =
      Runs.continuation_page("1", :forward,
        client: FakeJizokuClient,
        visibility_actor: "operator-id",
        visibility_policy: policy
      )

    assert [_row] = page.runs
    assert page.warning =~ "access was denied"
    refute inspect(page) =~ "hidden input"
  end

  test "projects conflict and pending terminalization as fixed warnings" do
    snapshot = %{
      run("1", "2")
      | terminal?: false,
        anomalies: [%{reason: :conflicting_continuation, details: "hidden conflict"}]
    }

    row = Continuation.project(snapshot)
    assert Enum.any?(row.warnings, &String.contains?(&1, "Conflicting"))
    assert Enum.any?(row.warnings, &String.contains?(&1, "terminalization"))
    refute inspect(row) =~ "hidden"
  end

  test "backward traversal follows only predecessor lineage" do
    FakeJizokuClient.put_inspect_run(fn id, _opts ->
      snapshot = run(id, "unrelated-successor")
      predecessor = if id == "2", do: %{run_id: "1", continuation_key: "roll"}
      {:ok, %{snapshot | continuation: %{snapshot.continuation | continued_from: predecessor}}}
    end)

    page = Runs.continuation_page("2", :backward, client: FakeJizokuClient)
    assert Enum.map(page.runs, & &1.run_id) == ["2", "1"]
  end

  defp run(id, next) do
    successor = if next, do: %{run_id: next, continuation_key: "roll-#{id}"}

    %{
      snapshot(:continued,
        run_id: id,
        workflow: "Recurring",
        terminal?: true,
        terminal_status: :continued,
        input: %{"secret" => "hidden input"}
      )
      | definition_version: "v1",
        continuation: %{continued_from: nil, continued_to: successor}
    }
  end
end
