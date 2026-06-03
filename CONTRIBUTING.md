# Contributing

SquidSonar is an embeddable Phoenix UI for inspecting Squidie workflow runs.
Keep changes small, focused, and easy to review.

## Development

Use the toolchain in `.tool-versions`, then run:

```bash
mix deps.get
mix precommit
```

`mix precommit` runs compile, format checks, and tests.

## Example App Coverage

Every user-facing feature should include matching example-app coverage when the
behavior can be demonstrated in a running Phoenix app. The example app should
make new dashboard behavior visible with real Squidie workflow data.

## Pull Requests

- Use Conventional Commits.
- Keep one coherent intent per PR.
- Include the exact verification commands you ran.
- Include screenshots or video for UI changes when practical.
- Do not include secrets, local paths, hostnames, or machine-specific metadata.
