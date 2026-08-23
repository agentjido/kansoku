# Kansoku Development Guide

## Intent

Kansoku is an embeddable Phoenix LiveView dashboard for Jizoku workflow runs.
Keep it focused on operator visibility and controls over the public Jizoku API.

## Runtime Baseline

- Elixir `~> 1.18`
- Erlang/OTP versions supported by the CI matrix
- Postgres for the example application

## Canonical Commands

- `mix deps.get`
- `mix compile`
- `mix test`
- `mix quality`
- `mix precommit`
- `mix coveralls`

## Architecture And Scope

- Keep Jizoku access behind `Kansoku.JizokuClient` when possible.
- Keep runtime behavior in Jizoku. Kansoku supplies presentation and operator controls.
- Keep example-only application wiring in `examples/example_app`.

## Standards And Conventions

- Use Conventional Commits.
- Use `mix format` for Elixir, HEEx, and configuration files.
- Do not add machine-specific paths, credentials, or deployment assumptions.

## Testing And QA

- Add focused tests for dashboard, router, and LiveView changes.
- Add example application coverage for user-visible behavior when practical.
- Run `mix precommit` before handoff.

## Release Hygiene And References

- Do not edit `CHANGELOG.md` in normal pull requests.
- Use the repository release workflow for package releases.
- Follow the Jido package quality standards at
  <https://jido.run/docs/contributors/package-quality-standards>.
