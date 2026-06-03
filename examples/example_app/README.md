# SquidSonar Example App

This Phoenix app demonstrates SquidSonar mounted inside a real host
application. It installs Squidie, defines a small set of workflow examples,
and exposes the embedded dashboard at `/sonar`.

Use it to try SquidSonar locally with realistic runtime data.

## Run Locally

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix example.seed
mix phx.server
```

Open `http://localhost:4000/sonar`.

The example server starts a small host-owned journal runner that repeatedly
calls `Squidie.execute_next/1`. This keeps the preview interactive: approving
or rejecting the manual review checkout records the decision, runs the follow-up
workflow step, and refreshes the run toward its terminal state.

## Included Workflow Runs

The seed task creates several Squidie runs so the dashboard has useful data
immediately:

- Completed checkout
- Failed checkout
- Retrying checkout
- Paused checkout that can be resumed
- Manual review checkout paused for approval

Each run can be opened from the dashboard to inspect status, current step,
diagnosis, attempt counts, history counts, last error metadata, and the
workflow graph.

## Verification

Run the example app test suite with:

```bash
mix precommit
```
