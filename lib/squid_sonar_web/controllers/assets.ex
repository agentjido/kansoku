defmodule SquidSonarWeb.Assets do
  @moduledoc false

  use Phoenix.Controller, formats: []

  @static_path Application.app_dir(:squid_sonar, "priv/static")
  @external_resource css_path = Path.join(@static_path, "squid_sonar.css")
  @css File.read!(css_path)
  @css_digest String.slice(Base.encode16(:crypto.hash(:md5, @css), case: :lower), 0, 8)

  @external_resource phoenix_path = Application.app_dir(:phoenix, "priv/static/phoenix.mjs")
  @phoenix_js File.read!(phoenix_path)
  @phoenix_digest String.slice(Base.encode16(:crypto.hash(:md5, @phoenix_js), case: :lower), 0, 8)

  @external_resource live_view_path =
                       Application.app_dir(
                         :phoenix_live_view,
                         "priv/static/phoenix_live_view.esm.js"
                       )
  @live_view_js File.read!(live_view_path)
  @live_view_digest String.slice(
                      Base.encode16(:crypto.hash(:md5, @live_view_js), case: :lower),
                      0,
                      8
                    )

  @js """
  import { Socket, LongPoll } from "./vendor/phoenix-#{@phoenix_digest}";
  import { LiveSocket } from "./vendor/live-view-#{@live_view_digest}";

  const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
  const script = document.querySelector("script[data-squid-sonar-client]");
  const livePath = script?.dataset.livePath || "/live";
  const liveTransport = script?.dataset.liveTransport || "websocket";
  const socketOptions = { params: { _csrf_token: csrfToken } };
  const themeStorageKey = "squid-sonar-theme";
  const themes = new Set(["system", "light", "dark"]);

  const storedTheme = () => {
    try {
      const theme = window.localStorage.getItem(themeStorageKey);
      return themes.has(theme) ? theme : null;
    } catch (_error) {
      return null;
    }
  };

  const storeTheme = (theme) => {
    if (!themes.has(theme)) return;

    try {
      window.localStorage.setItem(themeStorageKey, theme);
    } catch (_error) {
      return;
    }
  };

  const applyTheme = (theme) => {
    if (!themes.has(theme)) return;

    document.querySelectorAll(".squid-sonar-shell").forEach((shell) => {
      shell.classList.remove(
        "squid-sonar-theme-system",
        "squid-sonar-theme-light",
        "squid-sonar-theme-dark"
      );
      shell.classList.add(`squid-sonar-theme-${theme}`);
    });
  };

  const initialTheme = storedTheme();
  if (initialTheme) applyTheme(initialTheme);

  const Hooks = {
    SquidSonarTheme: {
      mounted() {
        const theme = storedTheme();
        if (theme) this.pushEvent("set_theme", { theme });
      }
    },
    SquidSonarFlash: {
      mounted() {
        this.scheduleDismiss();
      },
      updated() {
        this.scheduleDismiss();
      },
      destroyed() {
        window.clearTimeout(this.dismissTimer);
      },
      scheduleDismiss() {
        window.clearTimeout(this.dismissTimer);
        this.dismissTimer = window.setTimeout(() => this.pushEvent("clear_flash", {}), 5000);
      }
    },
    SquidSonarCopy: {
      mounted() {
        this.handleClick = async () => {
          const target = document.getElementById(this.el.dataset.copyTarget);
          if (!target) return;

          const text = target.textContent?.trim();
          if (!text) return;

          try {
            await navigator.clipboard.writeText(text);
            const label = this.el.dataset.copyLabel || "Copy";
            this.el.textContent = "Copied";
            this.el.setAttribute("aria-label", `${label}: copied`);
            window.setTimeout(() => {
              this.el.textContent = label;
              this.el.setAttribute("aria-label", label);
            }, 1500);
          } catch (_error) {
            this.el.textContent = "Copy failed";
            this.el.setAttribute("aria-label", "Copy failed");
          }
        };

        this.el.addEventListener("click", this.handleClick);
      },
      destroyed() {
        this.el.removeEventListener("click", this.handleClick);
      }
    }
  };

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-squid-sonar-theme]");
    if (!button) return;

    const theme = button.dataset.squidSonarTheme;
    storeTheme(theme);
    applyTheme(theme);
  });

  if (liveTransport === "longpoll") {
    socketOptions.transport = LongPoll;
  }

  socketOptions.hooks = Hooks;

  const liveSocket = new LiveSocket(livePath, Socket, socketOptions);
  liveSocket.connect();

  window.squidSonarLiveSocket = liveSocket;
  """
  @js_digest String.slice(Base.encode16(:crypto.hash(:md5, @js), case: :lower), 0, 8)

  @doc """
  Returns the cache digest for SquidSonar's packaged CSS asset.
  """
  @spec digest() :: String.t()
  def digest, do: @css_digest

  @doc """
  Returns the cache digest for SquidSonar's packaged JavaScript asset.
  """
  @spec js_digest() :: String.t()
  def js_digest, do: @js_digest

  @doc """
  Returns the cache digest for the packaged Phoenix JavaScript dependency.
  """
  @spec phoenix_digest() :: String.t()
  def phoenix_digest, do: @phoenix_digest

  @doc """
  Returns the cache digest for the packaged LiveView JavaScript dependency.
  """
  @spec live_view_digest() :: String.t()
  def live_view_digest, do: @live_view_digest

  @doc """
  Serves SquidSonar's packaged CSS asset when the digest matches.
  """
  @spec css(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def css(%{params: %{"digest" => digest}} = conn, _params) when digest == @css_digest do
    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @css)
  end

  def css(conn, _params) do
    send_resp(conn, 404, "Not Found")
  end

  @doc """
  Serves SquidSonar's packaged JavaScript asset when the digest matches.
  """
  @spec js(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def js(%{params: %{"digest" => digest}} = conn, _params) when digest == @js_digest do
    send_js(conn, @js)
  end

  def js(conn, _params) do
    send_resp(conn, 404, "Not Found")
  end

  @doc """
  Serves the packaged Phoenix JavaScript dependency when the digest matches.
  """
  @spec phoenix(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def phoenix(%{params: %{"digest" => digest}} = conn, _params) when digest == @phoenix_digest do
    send_js(conn, @phoenix_js)
  end

  def phoenix(conn, _params) do
    send_resp(conn, 404, "Not Found")
  end

  @doc """
  Serves the packaged LiveView JavaScript dependency when the digest matches.
  """
  @spec live_view(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_view(%{params: %{"digest" => digest}} = conn, _params)
      when digest == @live_view_digest do
    send_js(conn, @live_view_js)
  end

  def live_view(conn, _params) do
    send_resp(conn, 404, "Not Found")
  end

  defp send_js(conn, body) do
    conn
    |> put_resp_content_type("text/javascript")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, body)
  end
end
