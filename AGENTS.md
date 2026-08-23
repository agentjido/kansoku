# Kansoku Development Guide

## Intent

Kansoku is an embedded Phoenix LiveView dashboard for Jizoku workflow runs.
Keep the package focused on operator visibility and controls.

## Runtime Baseline

- Elixir `~> 1.18`
- Erlang/OTP versions in the CI matrix
- Postgres for the example application

## Canonical Commands

- `mix deps.get`
- `mix compile`
- `mix test`
- `mix quality`
- `mix precommit`
- `mix coveralls`

## Architecture And Scope

- Put Jizoku access behind `Kansoku.JizokuClient` when possible.
- Keep workflow runtime behavior in Jizoku.
- Keep application setup in `examples/example_app`.
- Keep the established `Kansoku` namespace until an approved breaking release.

## Standards And Conventions

- Use Conventional Commits.
- Use `mix format` for Elixir, HEEx, and configuration files.
- Install Git hooks only with `mix install_hooks` from the primary checkout.
- Do not add machine paths, credentials, or deployment assumptions.

## Testing And QA

- Add focused tests for dashboard, router, and LiveView changes.
- Add example application tests for visible behavior when practical.
- Run `mix precommit` before handoff.

## Release Hygiene And References

- Do not edit `CHANGELOG.md` in a normal pull request.
- Use the repository release workflow. Use its dry-run mode before a release.
- Follow the Jido package quality standards at
  <https://jido.run/docs/contributors/package-quality-standards>.
