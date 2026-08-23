# LLM Usage Rules For Kansoku

Kansoku provides an embedded Phoenix LiveView dashboard for Jizoku workflow runs.

## Working Rules

- Use public Jizoku inspection and control APIs.
- Put Jizoku access behind `Kansoku.JizokuClient` when possible.
- Keep durable workflow behavior in Jizoku, not in dashboard modules.
- Keep application setup in the host application or `examples/example_app`.
- Do not expose secrets, raw credentials, or unrestricted operator actions.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
