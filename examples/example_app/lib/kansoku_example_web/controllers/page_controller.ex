defmodule KansokuExampleWeb.PageController do
  use KansokuExampleWeb, :controller

  def home(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Kansoku Example</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; padding: 32px;">
        <h1>Kansoku Example</h1>
        <p>Use this app to exercise Jizoku workflows and monitor them in Kansoku.</p>
        <p><a href="/kansoku">Open Kansoku</a></p>
      </body>
    </html>
    """)
  end
end
