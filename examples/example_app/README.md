# Kansoku Example App

This Phoenix app demonstrates Kansoku mounted inside a real host
application. It installs Jizoku, defines a small set of workflow examples,
and exposes the embedded dashboard at `/kansoku`.

Use it to try Kansoku locally with realistic runtime data.

## Run Locally

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix example.seed
mix phx.server
```

Open `http://localhost:4000/kansoku`.

The example server starts a small host-owned journal runner that repeatedly
calls `Jizoku.execute_next/1`. This keeps the preview interactive: approving
or rejecting the manual review checkout records the decision, runs the follow-up
workflow step, and refreshes the run toward its terminal state.

## Included Workflow Runs

The seed task creates several Jizoku runs so the dashboard has useful data
immediately:

- Completed checkout
- Failed checkout
- Retrying checkout
- Deferred checkout waiting on a provider callback
- Saga checkout with compensation evidence
- Paused checkout that can be resumed
- Manual review checkout paused for approval

Each run can be opened from the dashboard to inspect status, current step,
diagnosis, attempt counts, history counts, last error metadata, and the
workflow graph.

The workflow graphs use the Jizoku DSL while their executable steps are raw
`Jido.Action` modules. This demonstrates the intended interop boundary in a
real Phoenix host: Jizoku owns durable orchestration and Kansoku observes and
controls the resulting runs without wrapping the underlying Jido primitives.

## Verification

Run the example app test suite with:

```bash
mix precommit
```
