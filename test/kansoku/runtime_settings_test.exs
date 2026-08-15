defmodule Kansoku.RuntimeSettingsTest do
  use ExUnit.Case, async: true

  alias Kansoku.FakeJizokuClient
  alias Kansoku.RuntimeSettings

  test "projects only allowlisted runtime metadata" do
    settings = %{
      live_transport: "longpoll",
      visibility_policy: :auditor,
      visibility_actor: "private-user",
      control_actor: %{"token" => "top-secret"},
      runtime_spec: %{module: Secret.Workflow, path: "/private/workflow"},
      runtime_specs: %{checkout: Secret.Checkout},
      saved_specs: [private: %{password: "hunter2"}],
      action_registry: %{"secret-action" => Secret.Action}
    }

    projection = RuntimeSettings.project(settings, client: FakeJizokuClient)
    json = RuntimeSettings.json(projection)

    assert projection.transport == "Long polling"
    assert projection.integration_status == "Ready"
    assert projection.visibility == "Auditor"
    assert projection.control_access == "Read-only"
    assert projection.runtime_specs_count == 1
    assert projection.saved_specs_count == 1
    assert projection.action_registry_configured

    for private_value <- [
          "private-user",
          "top-secret",
          "hunter2",
          "/private/workflow",
          "Secret.Workflow",
          "secret-action"
        ] do
      refute json =~ private_value
    end
  end

  test "uses safe labels for custom policies and absent catalogs" do
    projection =
      RuntimeSettings.project(
        %{visibility_policy: {Secret.Policy, password: "hidden"}},
        client: FakeJizokuClient
      )

    assert projection.visibility == "Custom policy"
    assert projection.control_access == "Read-only"
    refute projection.runtime_specs_configured
    refute projection.saved_specs_configured
    refute projection.action_registry_configured
  end

  test "reports a safe needs-attention status without exposing the client error" do
    FakeJizokuClient.put_list_runs({:error, {:missing_config, "/private/path", "secret"}})

    projection = RuntimeSettings.project(%{}, client: FakeJizokuClient)
    json = RuntimeSettings.json(projection)

    assert projection.integration_status == "Needs attention"
    refute json =~ "missing_config"
    refute json =~ "/private/path"
    refute json =~ "secret"
  end
end
