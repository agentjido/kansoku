defmodule KansokuExampleWeb.RouterTest do
  use ExUnit.Case, async: true

  test "mounts the example home page and Kansoku routes" do
    routes = Phoenix.Router.routes(KansokuExampleWeb.Router)

    assert Enum.any?(routes, &(&1.path == "/" and &1.plug == KansokuExampleWeb.PageController))
    assert Enum.any?(routes, &(&1.path == "/kansoku" and &1.plug == Phoenix.LiveView.Plug))
    assert Enum.any?(routes, &(&1.path == "/kansoku/queues" and &1.plug == Phoenix.LiveView.Plug))

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/saved-specs/:key" and &1.plug == Phoenix.LiveView.Plug)
           )

    refute Enum.any?(routes, &(&1.path == "/kansoku/runtime-specs/new"))

    assert Enum.any?(
             routes,
             &(&1.path == "/kansoku/css-:digest" and &1.plug == KansokuWeb.Assets)
           )
  end

  test "exposes multiple runtime spec catalog workflows" do
    runtime_specs = KansokuExample.RuntimeSpecDemo.runtime_specs(%Plug.Conn{})

    assert Keyword.fetch!(runtime_specs, :completed_checkout) ==
             KansokuExample.Workflows.CompletedCheckout

    assert Keyword.fetch!(runtime_specs, :invoice_reconciliation) ==
             KansokuExample.Workflows.InvoiceReconciliation

    assert Keyword.fetch!(runtime_specs, :retrying_checkout) ==
             KansokuExample.Workflows.RetryingCheckout

    assert Keyword.fetch!(runtime_specs, :scheduled_reconciliation) ==
             KansokuExample.Workflows.ScheduledReconciliation

    assert length(runtime_specs) > 1
  end

  test "configures the runtime spec start example" do
    routes = Phoenix.Router.routes(KansokuExampleWeb.Router)

    assert %{metadata: %{phoenix_live_view: {_live, _action, _route_opts, live_opts}}} =
             Enum.find(routes, &(&1.path == "/kansoku"))

    assert {Kansoku.Router, :__session__,
            [
              _prefix,
              _live_path,
              _live_transport,
              _control_actor,
              runtime_spec,
              action_registry,
              runtime_options
            ]} =
             live_opts.extra.session

    assert runtime_spec == nil
    assert action_registry == {KansokuExample.RuntimeSpecDemo, :action_registry, []}

    assert runtime_options == %{
             saved_specs: {KansokuExample.RuntimeSpecDemo, :saved_specs, []},
             runtime_specs: {KansokuExample.RuntimeSpecDemo, :runtime_specs, []}
           }
  end

  test "seeds an approved saved runtime spec" do
    saved_specs = KansokuExample.RuntimeSpecDemo.saved_specs(%Plug.Conn{})
    saved_spec = Keyword.fetch!(saved_specs, :checkout_runtime_spec)

    assert saved_spec.status == :approved
    assert saved_spec.editor_json["workflow"] =~ "CompletedCheckout"
    assert is_map(saved_spec.source_spec)
    assert is_map(saved_spec.spec)
  end
end
