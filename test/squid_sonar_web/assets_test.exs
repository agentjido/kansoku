defmodule SquidSonarWeb.AssetsTest do
  use ExUnit.Case, async: true

  test "serves packaged CSS for the current digest" do
    digest = SquidSonarWeb.Assets.digest()

    conn =
      :get
      |> Plug.Test.conn("/sonar/css-#{digest}")
      |> Map.put(:params, %{"digest" => digest})
      |> SquidSonarWeb.Assets.css(%{})

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
    assert conn.resp_body =~ ".squid-sonar-shell"
    assert conn.resp_body =~ ".squid-sonar-refresh.phx-click-loading"
    assert conn.resp_body =~ "--squid-sonar-accent: #8061d8;"
    assert conn.resp_body =~ ".squid-sonar-nav-item.is-active::before"
    assert conn.resp_body =~ ".squid-sonar-nav-item:hover::before"
    assert conn.resp_body =~ ".squid-sonar-nav-item:hover strong"
    assert conn.resp_body =~ ".squid-sonar-badge"
    assert conn.resp_body =~ ".squid-sonar-queue-content"
    assert conn.resp_body =~ ".squid-sonar-schedule-status"

    assert conn.resp_body =~
             ~r/\.squid-sonar-filter-controls\s*\{[^}]*grid-template-columns: repeat\(4,/s

    assert conn.resp_body =~ ".squid-sonar-advanced-filters"
    assert conn.resp_body =~ ".squid-sonar-saved-workflows-slot"
    assert conn.resp_body =~ ".squid-sonar-saved-workflows-content"
    assert conn.resp_body =~ ".squid-sonar-panel-heading h2"
    assert conn.resp_body =~ ".squid-sonar-filter-controls-primary"

    assert conn.resp_body =~
             ~r/\.squid-sonar-panel-heading\s*\{[^}]*min-height: 0;[^}]*padding: var\(--squid-sonar-space-2\)/s

    assert conn.resp_body =~ "border-radius: 4px"

    assert conn.resp_body =~
             ".squid-sonar-filter-toggle-input:checked + form .squid-sonar-sidebar"

    assert conn.resp_body =~
             ~r/\.squid-sonar-flash-close:hover\s*\{[^}]*background: transparent;[^}]*box-shadow: inset 0 0 0 1px var\(--squid-sonar-border-strong\);[^}]*color: var\(--squid-sonar-muted\);/s

    refute conn.resp_body =~ "gradient"
    # box-shadow is now used for control button hover effects
    refute conn.resp_body =~ "text-shadow"
    refute conn.resp_body =~ "#315f8f"
    refute conn.resp_body =~ "#8aa4c8"
  end

  test "rejects stale CSS digests" do
    conn =
      :get
      |> Plug.Test.conn("/sonar/css-stale")
      |> Map.put(:params, %{"digest" => "stale"})
      |> SquidSonarWeb.Assets.css(%{})

    assert conn.status == 404
  end

  test "serves packaged JavaScript for the current digest" do
    digest = SquidSonarWeb.Assets.js_digest()

    conn =
      :get
      |> Plug.Test.conn("/sonar/js-#{digest}")
      |> Map.put(:params, %{"digest" => digest})
      |> SquidSonarWeb.Assets.js(%{})

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert conn.resp_body =~ "new LiveSocket"
    assert conn.resp_body =~ "squid-sonar-theme"
    assert conn.resp_body =~ "SquidSonarTheme"
    assert conn.resp_body =~ "SquidSonarFlash"
    assert conn.resp_body =~ "SquidSonarCopy"
    assert conn.resp_body =~ "navigator.clipboard.writeText"
    assert conn.resp_body =~ "target.textContent"
  end

  test "serves packaged LiveView client dependencies" do
    assert_asset_response(:phoenix, "Socket")
    assert_asset_response(:live_view, "LiveSocket")
  end

  defp assert_asset_response(action, expected_body) do
    digest = asset_digest(action)

    request_conn =
      :get
      |> Plug.Test.conn("/sonar/vendor/#{action}-#{digest}")
      |> Map.put(:params, %{"digest" => digest})

    conn = apply(SquidSonarWeb.Assets, action, [request_conn, %{}])

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert conn.resp_body =~ expected_body
  end

  defp asset_digest(:phoenix), do: SquidSonarWeb.Assets.phoenix_digest()
  defp asset_digest(:live_view), do: SquidSonarWeb.Assets.live_view_digest()
end
