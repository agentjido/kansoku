defmodule SquidSonarExampleWeb.PageController do
  use SquidSonarExampleWeb, :controller

  def home(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>SquidSonar Example</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; padding: 32px;">
        <h1>SquidSonar Example</h1>
        <p>Use this app to exercise Squidie workflows and monitor them in SquidSonar.</p>
        <p><a href="/sonar">Open SquidSonar</a></p>
      </body>
    </html>
    """)
  end
end
