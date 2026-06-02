# SquidSonar

<div align="left">
  <p>
    <a href="https://github.com/dark-trench/squid_sonar/actions/workflows/ci.yml">
      <img alt="CI" src="https://github.com/dark-trench/squid_sonar/actions/workflows/ci.yml/badge.svg" />
    </a>
    <a href="https://hex.pm/packages/squid_sonar">
      <img alt="Hex" src="https://img.shields.io/hexpm/v/squid_sonar" />
    </a>
    <a href="https://hexdocs.pm/squid_sonar">
      <img alt="HexDocs" src="https://img.shields.io/badge/docs-hexdocs-purple" />
    </a>
    <a href="https://github.com/dark-trench/squid_sonar/blob/main/LICENSE">
      <img alt="License: Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" />
    </a>
  </p>
</div>

SquidSonar is a read-only Phoenix LiveView dashboard for applications that run
Squid Mesh workflows.

Mount it inside a Phoenix host application to inspect recent runs, filter by
status, search runtime metadata, and open detail pages with the workflow graph,
diagnosis, attempt counts, history counts, and last error information.

<img width="1361" height="592" alt="Screenshot 2026-05-29 at 10 53 44" src="https://github.com/user-attachments/assets/6a60b7f8-2c8a-4c30-b304-488a0ce17a4f" />
<img width="1396" height="937" alt="Screenshot 2026-05-29 at 10 53 57" src="https://github.com/user-attachments/assets/fe8ff3af-f9c3-4d95-be09-59b952ea85e4" />

## Runtime Boundary

SquidSonar is distributed as an embeddable library, not a standalone service. A
host Phoenix application owns authentication, authorization, deployment,
endpoint configuration, and the Squid Mesh runtime. SquidSonar contributes the
router macro, LiveViews, static assets, and a small read boundary over Squid
Mesh public APIs.

SquidSonar interacts with Squid Mesh through:

### Read Operations
- `SquidMesh.list_runs/2`
- `SquidMesh.inspect_run/2`
- `SquidMesh.inspect_run_graph/2`
- `SquidMesh.explain_run/2`

### Control Operations
- `SquidMesh.cancel/2` - Cancel running workflows
- `SquidMesh.resume/3` - Resume paused workflows
- `SquidMesh.approve/3` - Approve manual approval steps
- `SquidMesh.reject/3` - Reject manual approval steps
- `SquidMesh.replay/2` - Replay completed workflows

Host applications still own workers, queue delivery, scheduler
setup, and backend leasing or fencing. When a Squid Mesh host uses Bedrock or
another delivery backend, that adapter remains part of the host application, not
SquidSonar.

```text
Phoenix Host Application
|
+-- Squid Mesh runtime
|   +-- workers
|   +-- scheduler and delivery backend
|   +-- lease or fencing adapter when needed
|
+-- SquidSonar
    +-- router macro
    +-- read-only LiveViews
    +-- embedded assets
    +-- Squid Mesh inspection API client
```

## Dashboard Surface

The UI includes:

- Recent workflow runs sorted by update time
- Status counts and filters
- Search across workflow, trigger, step, status, and run ID
- Page size controls and pagination
- Run detail pages with diagnosis, history counts, last error, and workflow
  graph visualization
- Recovery metadata on compensatable graph nodes when Squid Mesh exposes
  rollback policy information
- Recovery policy summaries that distinguish declared rollback callbacks,
  non-compensatable steps, and manual-review replay boundaries
- Deadline and escalation evidence when Squid Mesh exposes step SLA state,
  including due-soon, overdue, and escalated run filters
- Step attempt counts on run detail pages
- Light, dark, and system theme controls
- Embedded CSS and JavaScript served by the library

SquidSonar only displays deadline and escalation state returned by Squid Mesh.
Alert delivery, notification routing, paging rules, and escalation side effects
remain host-application responsibilities.

## Requirements

- Elixir 1.17 or later
- Phoenix 1.8
- Phoenix LiveView 1.1
- A host application with Squid Mesh installed and configured

## Installation

Add SquidSonar to the host application's dependencies:

```elixir
def deps do
  [
    {:squid_sonar, "~> 0.1.7"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Mounting

Import `SquidSonar.Router` in the host router and mount the dashboard under the
path that makes sense for the application:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use SquidSonar.Router

  scope "/ops" do
    pipe_through [:browser, :require_authenticated_user]

    squid_sonar "/sonar"
  end
end
```

Visit `/ops/sonar` to open the dashboard.

SquidSonar accepts a few route-level options:

```elixir
squid_sonar "/sonar",
  as: :runtime_sonar,
  socket_path: "/live",
  transport: "websocket",
  control_actor: {MyAppWeb.SquidSonarAudit, :control_actor, []}
```

`transport` can be `"websocket"` or `"longpoll"`.

`control_actor` is persisted with Squid Mesh manual actions such as resume,
approve, and reject. It can be a non-empty string, a non-empty map, or an MFA
tuple. MFA callbacks receive the current `Plug.Conn` as their first argument.
Prefer a small audit map over a raw user struct:

```elixir
defmodule MyAppWeb.SquidSonarAudit do
  def control_actor(conn) do
    user = conn.assigns.current_user

    %{
      "type" => "user",
      "id" => user.id,
      "email" => user.email
    }
  end
end
```

If omitted, SquidSonar uses a placeholder actor so local demos can exercise
manual controls. Production mounts should pass the authenticated operator once
the host app wires SquidSonar into its own auth pipeline.

## Security

SquidSonar does not ship its own authentication layer. Protect the mounted route
with the same browser pipeline, session handling, and authorization rules used
for the rest of the host application's operator surface.

The dashboard can issue Squid Mesh control actions when a run exposes safe
manual actions. It also displays runtime data returned by Squid Mesh, including
workflow names, run IDs, step names, statuses, diagnostic signals, and selected
error metadata. Treat the mounted dashboard as an operational control surface
and expose it only to trusted users.

Run list and run detail pages refresh automatically while they are open. Detail
pages poll active runs and run list pages reload the current filtered view, so
manual controls can reflect follow-up workflow work without a browser refresh.

## Example App

The repository includes a Phoenix example app at `examples/example_app`. It
mounts SquidSonar at `/sonar` and seeds real Squid Mesh workflows that produce
completed, failed, retrying, paused, approval-paused, and saga recovery runs.
The saga recovery run includes a compensatable inventory reservation step so
the dashboard can show declared rollback metadata and recovery policy
diagnostics without calling rollback code. The example server also starts a
small host-owned journal runner, so dashboard control actions such as approving
or rejecting the manual review checkout can advance their scheduled follow-up
steps during local preview.

```bash
cd examples/example_app
mix deps.get
mix ecto.create
mix ecto.migrate
mix example.seed
mix phx.server
```

Open `http://localhost:4000/sonar` after the server starts.

## Library Modules

- `SquidSonar.Router` mounts the embedded dashboard routes.
- `SquidSonar.Runs` is the read boundary over Squid Mesh run APIs.
- `SquidSonar.Dashboard` builds the filtered, paginated dashboard snapshot.
- `SquidSonar.Runs.WorkflowGraph` turns workflow definitions and persisted run
  state into a display graph.
- `SquidSonarWeb.*` contains the embedded LiveViews, components, layout, hooks,
  and asset controller.

## Community

Use the [Squid Mesh Elixir Forum thread](https://elixirforum.com/t/squid-mesh-workflow-automation-runtime-for-elixir-applications/75162)
for public discussion and design context around the runtime and dashboard.

Use [GitHub issues](https://github.com/dark-trench/squid_sonar/issues) for
dashboard bugs, feature requests, and release-tracked work.

For informal runtime and Jido-adjacent chat, use the
[Squid Mesh channel on the Jido Discord](https://discord.com/channels/1323353012235796550/1504122798027571331).

## License

Apache-2.0
