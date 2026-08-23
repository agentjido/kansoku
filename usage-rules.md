# LLM Usage Rules For Kansoku

Kansoku provides an embeddable Phoenix LiveView dashboard for Jizoku workflow runs.

## Working Rules

- Use public Jizoku inspection and control APIs.
- Keep Jizoku access behind `Kansoku.JizokuClient` when possible.
- Keep durable workflow behavior in Jizoku, not in dashboard modules.
- Keep application-specific setup in the host application or `examples/example_app`.
- Do not expose secrets, raw credentials, or unrestricted operator actions in the UI.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
