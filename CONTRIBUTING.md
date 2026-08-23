# Contributing

Kansoku is an embeddable Phoenix UI for inspecting Jizoku workflow runs.
Keep changes small, focused, and easy to review.

## Development

Use the toolchain in `.tool-versions`, then run:

```bash
mix deps.get
mix quality
mix test
```

`mix quality` runs the shared Jido package quality checks. `mix precommit` adds
Kansoku-specific audits, structural checks, and tests.

Install the Conventional Commit hook only from the primary checkout:

```bash
mix install_hooks
```

See the [Jido package quality standards](https://jido.run/docs/contributors/package-quality-standards)
for the ecosystem maintenance baseline.

## Quality Gates

The repo includes strict quality-gate aliases for duplicate-code and code-flow
review:

```bash
mix quality_gates
mix quality_gates.ex_dna
mix quality_gates.reach
```

Current tool versions are `ex_dna` 1.5.2 and `reach` 2.7.1. Both are
dev/test-only dependencies with `runtime: false`.

`mix quality_gates.ex_dna` runs
`mix ex_dna --min-mass 40 --max-clones 0 --format console`. This fails on any
reported clone at the configured mass threshold.

`mix quality_gates.reach` runs `mix reach.check --smells --strict`. This fails
on any Reach smell finding.

These checks are part of `mix precommit` and CI. Do not bundle broad cleanup
with unrelated changes. Fix meaningful findings in the smallest behavior-safe
slice, and suppress an intentional finding only when the source comment explains
the domain reason it should remain.

## Example App Coverage

Every user-facing feature should include matching example-app coverage when the
behavior can be demonstrated in a running Phoenix app. The example app should
make new dashboard behavior visible with real Jizoku workflow data.

## Pull Requests

- Use Conventional Commits.
- Keep one coherent intent per PR.
- Include the exact verification commands you ran.
- Include screenshots or video for UI changes when practical.
- Do not include secrets, local paths, hostnames, or machine-specific metadata.

## Releases

The **Release** GitHub Actions workflow uses the shared Jido release process.
For a safe preparation check, run it on the target branch with `operation` set
to `auto` and `dry_run` set to `true`. A dry run does not push a commit or tag,
create a GitHub release, or publish to Hex.

A real release stays disabled until the repository variable
`KANSOKU_RELEASES_ENABLED` is `true`. It also needs a publish-capable
`HEX_API_KEY` secret. Do not enable the variable until the key and release plan
are ready.
