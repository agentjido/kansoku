defmodule SquidSonarExampleWeb.RouterTest do
  use ExUnit.Case, async: true

  test "mounts the example home page and SquidSonar routes" do
    routes = Phoenix.Router.routes(SquidSonarExampleWeb.Router)

    assert Enum.any?(routes, &(&1.path == "/" and &1.plug == SquidSonarExampleWeb.PageController))
    assert Enum.any?(routes, &(&1.path == "/sonar" and &1.plug == Phoenix.LiveView.Plug))

    refute Enum.any?(routes, &(&1.path == "/sonar/runtime-specs/new"))

    assert Enum.any?(
             routes,
             &(&1.path == "/sonar/css-:digest" and &1.plug == SquidSonarWeb.Assets)
           )
  end

  test "exposes multiple runtime spec catalog workflows" do
    runtime_specs = SquidSonarExample.RuntimeSpecDemo.runtime_specs(%Plug.Conn{})

    assert Keyword.fetch!(runtime_specs, :completed_checkout) ==
             SquidSonarExample.Workflows.CompletedCheckout

    assert Keyword.fetch!(runtime_specs, :invoice_reconciliation) ==
             SquidSonarExample.Workflows.InvoiceReconciliation

    assert Keyword.fetch!(runtime_specs, :retrying_checkout) ==
             SquidSonarExample.Workflows.RetryingCheckout

    assert length(runtime_specs) > 1
  end

  test "configures the runtime spec start example" do
    routes = Phoenix.Router.routes(SquidSonarExampleWeb.Router)

    assert %{metadata: %{phoenix_live_view: {_live, _action, _route_opts, live_opts}}} =
             Enum.find(routes, &(&1.path == "/sonar"))

    assert {SquidSonar.Router, :__session__,
            [
              _prefix,
              _live_path,
              _live_transport,
              _control_actor,
              runtime_spec,
              action_registry,
              runtime_specs
            ]} =
             live_opts.extra.session

    assert runtime_spec == nil
    assert action_registry == {SquidSonarExample.RuntimeSpecDemo, :action_registry, []}
    assert runtime_specs == {SquidSonarExample.RuntimeSpecDemo, :runtime_specs, []}
  end
end
