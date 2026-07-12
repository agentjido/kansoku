defmodule SquidSonarWeb.SettingsLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Phoenix.LiveView.Socket
  alias SquidSonarWeb.SettingsLive

  test "renders a read-only safe settings projection" do
    socket =
      %Socket{}
      |> assign(:prefix, "/sonar")
      |> assign(:live_transport, "websocket")
      |> assign(:visibility_policy, :operator)
      |> assign(:visibility_actor, "private-user")
      |> assign(:control_actor, %{"token" => "top-secret"})
      |> assign(:runtime_specs, %{checkout: Secret.Checkout})
      |> assign(:saved_specs, private: %{password: "hunter2"})
      |> assign(:action_registry, %{"secret-action" => Secret.Action})

    assert {:ok, mounted_socket} = SettingsLive.mount(%{}, %{}, socket)
    html = rendered_to_string(SettingsLive.render(mounted_socket.assigns))

    assert html =~ "Runtime settings"
    assert html =~ "Operator controls enabled"
    assert html =~ "Safe JSON"
    assert html =~ ~s(href="/sonar/settings")
    assert html =~ ~s(phx-hook="SquidSonarCopy")

    for private_value <- [
          "private-user",
          "top-secret",
          "hunter2",
          "Secret.Checkout",
          "secret-action"
        ] do
      refute html =~ private_value
    end
  end
end
