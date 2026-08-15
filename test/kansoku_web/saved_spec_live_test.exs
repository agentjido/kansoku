defmodule KansokuWeb.SavedSpecLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveViewTest
  import Kansoku.ReadModelFixtures

  alias Kansoku.FakeJizokuClient
  alias KansokuWeb.SavedSpecLive
  alias Phoenix.LiveView.Socket

  defmodule TestAction do
    use Jido.Action,
      name: "saved_spec_test_action",
      description: "test action",
      schema: [],
      output_schema: []

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{}}
  end

  setup do
    previous_client = Application.get_env(:kansoku, :jizoku_client)
    Application.put_env(:kansoku, :jizoku_client, FakeJizokuClient)

    on_exit(fn ->
      if previous_client do
        Application.put_env(:kansoku, :jizoku_client, previous_client)
      else
        Application.delete_env(:kansoku, :jizoku_client)
      end
    end)
  end

  test "renders validation, graph preview, raw JSON, and source diff for a saved spec" do
    {:ok, socket} =
      mount_saved_spec(
        "checkout_runtime_spec",
        checkout_runtime_spec: %{
          title: "Checkout runtime spec",
          status: :approved,
          editor_json: editor_json(),
          source_spec: source_editor_json(),
          spec: runtime_spec()
        }
      )

    html =
      socket.assigns
      |> SavedSpecLive.render()
      |> rendered_to_string()

    assert html =~ "Checkout runtime spec"
    assert html =~ "Approved"
    assert html =~ "Valid"
    assert html =~ "Graph preview"
    assert html =~ "load_order"
    assert html =~ "capture_payment"
    assert html =~ "Raw editor JSON"
    assert html =~ "Raw runtime spec"
    assert html =~ "Source diff"
    assert html =~ "nodes_added"
  end

  test "renders unknown and disabled action validation errors without leaking details" do
    {:ok, unknown_socket} =
      mount_saved_spec(
        "unknown_action",
        [unknown_action: %{title: "Unknown action", editor_json: editor_json("missing_action")}],
        %{}
      )

    unknown_html =
      unknown_socket.assigns
      |> SavedSpecLive.render()
      |> rendered_to_string()

    assert unknown_html =~ "Invalid"
    assert unknown_html =~ "steps.0.action"
    assert unknown_html =~ "references unknown action key"
    refute unknown_html =~ "do-not-render"

    {:ok, disabled_socket} =
      mount_saved_spec(
        "disabled_action",
        [disabled_action: %{title: "Disabled action", editor_json: editor_json("load_order")}],
        %{"load_order" => %{module: __MODULE__, enabled?: false}}
      )

    disabled_html =
      disabled_socket.assigns
      |> SavedSpecLive.render()
      |> rendered_to_string()

    assert disabled_html =~ "references disabled action key"
  end

  test "starts an approved saved spec through the runtime spec start boundary" do
    registry = %{
      "load_order" => TestAction,
      "capture_payment" => TestAction
    }

    spec = runtime_spec()
    payload = %{"order_id" => "order-1"}
    normalized_payload = %{order_id: "order-1"}

    FakeJizokuClient.put_start_spec(fn started_spec, started_payload, opts ->
      send(self(), {:start_spec, started_spec, started_payload, opts})

      {:ok,
       snapshot(:running,
         run_id: "saved-spec-run",
         workflow: "RuntimeCheckout",
         reason: :attempt_visible
       )}
    end)

    {:ok, socket} =
      mount_saved_spec(
        "checkout_runtime_spec",
        [
          checkout_runtime_spec: %{
            title: "Checkout runtime spec",
            status: :approved,
            editor_json: editor_json(),
            spec: spec
          }
        ],
        registry
      )

    {:noreply, started_socket} =
      SavedSpecLive.handle_event(
        "start_saved_spec",
        %{"saved_spec_start" => %{"payload_json" => Jason.encode!(payload)}},
        socket
      )

    assert_received {:start_spec, ^spec, ^normalized_payload, [action_registry: ^registry]}
    assert {:live, :redirect, %{to: "/kansoku/runs/saved-spec-run"}} = started_socket.redirected
  end

  test "preserves edited payload JSON when runtime spec start fails" do
    registry = %{
      "load_order" => TestAction,
      "capture_payment" => TestAction
    }

    spec = runtime_spec()
    edited_payload_json = Jason.encode!(%{"order_id" => "retry-order"}, pretty: true)

    FakeJizokuClient.put_start_spec(fn started_spec, started_payload, opts ->
      send(self(), {:start_spec, started_spec, started_payload, opts})

      {:error, :failed_to_start}
    end)

    {:ok, socket} =
      mount_saved_spec(
        "checkout_runtime_spec",
        [
          checkout_runtime_spec: %{
            title: "Checkout runtime spec",
            status: :approved,
            editor_json: editor_json(),
            spec: spec
          }
        ],
        registry
      )

    {:noreply, error_socket} =
      SavedSpecLive.handle_event(
        "start_saved_spec",
        %{"saved_spec_start" => %{"payload_json" => edited_payload_json}},
        socket
      )

    assert_received {:start_spec, ^spec, %{order_id: "retry-order"}, [action_registry: ^registry]}
    assert error_socket.assigns.saved_spec_payload_json == edited_payload_json

    html =
      error_socket.assigns
      |> SavedSpecLive.render()
      |> rendered_to_string()

    assert html =~ "Workflow start failed."
    assert html =~ "retry-order"
  end

  test "uses a neutral error when a saved spec is not startable" do
    {:ok, socket} =
      mount_saved_spec(
        "checkout_runtime_spec",
        checkout_runtime_spec: %{
          title: "Checkout runtime spec",
          status: :approved,
          editor_json: editor_json()
        }
      )

    {:noreply, error_socket} =
      SavedSpecLive.handle_event(
        "start_saved_spec",
        %{"saved_spec_start" => %{"payload_json" => Jason.encode!(%{"order_id" => "order-1"})}},
        socket
      )

    assert error_socket.assigns.saved_spec_start_error == "Saved workflow spec is not startable."
  end

  test "sets theme from the saved spec detail page" do
    {:ok, socket} =
      mount_saved_spec(
        "checkout_runtime_spec",
        checkout_runtime_spec: %{
          title: "Checkout runtime spec",
          status: :approved,
          editor_json: editor_json()
        }
      )

    {:noreply, themed_socket} =
      SavedSpecLive.handle_event("set_theme", %{"theme" => "light"}, socket)

    html =
      themed_socket.assigns
      |> SavedSpecLive.render()
      |> rendered_to_string()

    assert html =~ "kansoku-theme-light"
    refute html =~ "kansoku-theme-dark"
  end

  defp mount_saved_spec(key, saved_specs, registry \\ nil) do
    socket =
      %Socket{}
      |> assign(:prefix, "/kansoku")
      |> assign(:saved_specs, saved_specs)
      |> assign(:action_registry, registry)

    SavedSpecLive.mount(%{"key" => key}, %{}, socket)
  end

  defp runtime_spec do
    %{
      workflow: RuntimeCheckout,
      triggers: [%{name: :manual, type: :manual, config: %{}, payload: []}],
      payload: [%{name: :order_id, type: :string, opts: []}],
      steps: [
        %{name: :load_order, action: "load_order", module: :log, opts: [message: "load order"]},
        %{
          name: :capture_payment,
          action: "capture_payment",
          module: :log,
          opts: [message: "capture payment"]
        }
      ],
      transitions: [
        %{from: :load_order, on: :ok, to: :capture_payment},
        %{from: :capture_payment, on: :ok, to: :complete}
      ],
      retries: [],
      entry_steps: [:load_order],
      initial_step: :load_order,
      entry_step: :load_order
    }
  end

  defp source_editor_json do
    %{
      editor_json()
      | "steps" => [%{"name" => "load_order", "action" => "load_order", "opts" => %{}}],
        "transitions" => [%{"from" => "load_order", "on" => "ok", "to" => "complete"}]
    }
  end

  defp editor_json(action \\ "load_order") do
    %{
      "workflow" => "RuntimeCheckout",
      "triggers" => [%{"name" => "manual", "type" => "manual", "config" => %{}, "payload" => []}],
      "payload" => [%{"name" => "order_id", "type" => "string", "opts" => []}],
      "steps" => [
        %{"name" => "load_order", "action" => action, "opts" => %{}},
        %{"name" => "capture_payment", "action" => "capture_payment", "opts" => %{}}
      ],
      "transitions" => [
        %{"from" => "load_order", "on" => "ok", "to" => "capture_payment"},
        %{"from" => "capture_payment", "on" => "ok", "to" => "complete"}
      ],
      "retries" => [],
      "entry_steps" => ["load_order"],
      "initial_step" => "load_order",
      "entry_step" => "load_order"
    }
  end
end
