defmodule KansokuWeb.AssetsTest do
  use ExUnit.Case, async: true

  test "serves packaged CSS for the current digest" do
    digest = KansokuWeb.Assets.digest()

    conn =
      :get
      |> Plug.Test.conn("/kansoku/css-#{digest}")
      |> Map.put(:params, %{"digest" => digest})
      |> KansokuWeb.Assets.css(%{})

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
    assert conn.resp_body =~ ".kansoku-shell"
    assert conn.resp_body =~ ".kansoku-refresh.phx-click-loading"
    assert conn.resp_body =~ "--kansoku-accent: #8061d8;"
    assert conn.resp_body =~ ".kansoku-nav-item.is-active::before"
    assert conn.resp_body =~ ".kansoku-nav-item:hover::before"
    assert conn.resp_body =~ ".kansoku-nav-item:hover strong"
    assert conn.resp_body =~ ".kansoku-badge"
    assert conn.resp_body =~ ".kansoku-queue-content"
    assert conn.resp_body =~ ".kansoku-schedule-status"

    assert conn.resp_body =~
             ~r/\.kansoku-filter-controls\s*\{[^}]*grid-template-columns: repeat\(4,/s

    assert conn.resp_body =~ ".kansoku-advanced-filters"
    assert conn.resp_body =~ ".kansoku-reset-filters"
    assert conn.resp_body =~ ".kansoku-saved-workflows-slot"
    assert conn.resp_body =~ ".kansoku-saved-workflows-content"
    assert conn.resp_body =~ ".kansoku-run-jump-control"
    assert conn.resp_body =~ ".kansoku-run-jump-control:focus-within"
    assert conn.resp_body =~ ".kansoku-run-tabs"
    assert conn.resp_body =~ ".kansoku-run-tab:focus-visible"
    assert conn.resp_body =~ ".kansoku-timeline-list"
    assert conn.resp_body =~ ".kansoku-attempt-list"
    assert conn.resp_body =~ "--kansoku-topbar-control-height: 32px"
    assert conn.resp_body =~ ".kansoku-start-workflow-button"
    assert conn.resp_body =~ ".kansoku-runs-table th:first-child"
    assert conn.resp_body =~ "width: 40%"

    refute conn.resp_body =~
             ~r/\.kansoku-saved-workflows-slot\s*\{[^}]*background:/s

    assert conn.resp_body =~ ".kansoku-panel-heading h2"
    assert conn.resp_body =~ ".kansoku-filter-controls-primary"

    assert conn.resp_body =~
             ~r/\.kansoku-panel-heading\s*\{[^}]*min-height: 0;[^}]*padding: var\(--kansoku-space-2\)/s

    assert conn.resp_body =~ "border-radius: 4px"

    assert conn.resp_body =~
             ".kansoku-filter-toggle-input:checked + form .kansoku-sidebar"

    assert conn.resp_body =~
             ~r/\.kansoku-flash-close:hover\s*\{[^}]*background: transparent;[^}]*box-shadow: inset 0 0 0 1px var\(--kansoku-border-strong\);[^}]*color: var\(--kansoku-muted\);/s

    refute conn.resp_body =~ "gradient"
    # box-shadow is now used for control button hover effects
    refute conn.resp_body =~ "text-shadow"
    refute conn.resp_body =~ "#315f8f"
    refute conn.resp_body =~ "#8aa4c8"
  end

  test "rejects stale CSS digests" do
    conn =
      :get
      |> Plug.Test.conn("/kansoku/css-stale")
      |> Map.put(:params, %{"digest" => "stale"})
      |> KansokuWeb.Assets.css(%{})

    assert conn.status == 404
  end

  test "serves packaged JavaScript for the current digest" do
    digest = KansokuWeb.Assets.js_digest()

    conn =
      :get
      |> Plug.Test.conn("/kansoku/js-#{digest}")
      |> Map.put(:params, %{"digest" => digest})
      |> KansokuWeb.Assets.js(%{})

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert conn.resp_body =~ "new LiveSocket"
    assert conn.resp_body =~ "kansoku-theme"
    assert conn.resp_body =~ "KansokuTheme"
    assert conn.resp_body =~ "KansokuFlash"
    assert conn.resp_body =~ "KansokuCopy"
    assert conn.resp_body =~ "navigator.clipboard.writeText"
    assert conn.resp_body =~ "target.textContent"
    assert conn.resp_body =~ "dataset.copyText"
    assert conn.resp_body =~ "this.el.textContent = displayText"
  end

  test "serves packaged LiveView client dependencies" do
    assert_asset_response(:phoenix, "Socket")
    assert_asset_response(:live_view, "LiveSocket")
  end

  defp assert_asset_response(action, expected_body) do
    digest = asset_digest(action)

    request_conn =
      :get
      |> Plug.Test.conn("/kansoku/vendor/#{action}-#{digest}")
      |> Map.put(:params, %{"digest" => digest})

    conn = apply(KansokuWeb.Assets, action, [request_conn, %{}])

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert conn.resp_body =~ expected_body
  end

  defp asset_digest(:phoenix), do: KansokuWeb.Assets.phoenix_digest()
  defp asset_digest(:live_view), do: KansokuWeb.Assets.live_view_digest()
end
