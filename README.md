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

SquidSonar is an embeddable Phoenix LiveView operator dashboard for
applications that run Squidie workflows.

Mount it inside a Phoenix host application to inspect recent runs, filter by
status, search runtime metadata, and open detail pages with the workflow graph,
diagnosis, attempt counts, history counts, and last error information. It also
exposes Squidie control operations such as cancel, resume, approval, rejection,
replay, and runtime-spec starts when the host application wires the required
operator context.

## Runtime Boundary

SquidSonar is distributed as an embeddable library, not a standalone service. A
host Phoenix application owns authentication, authorization, deployment,
endpoint configuration, and the Squidie runtime. SquidSonar contributes the
router macro, LiveViews, static assets, and a bounded operator surface over
Squidie public APIs.

SquidSonar interacts with Squidie through:

### Read Operations
- `Squidie.list_runs/2`
- `Squidie.inspect_run/2`
- `Squidie.inspect_run_graph/2`
- `Squidie.explain_run/2`

### Control Operations
- `Squidie.cancel/2` - Cancel running workflows
- `Squidie.resume/3` - Resume paused workflows
- `Squidie.approve/3` - Approve manual approval steps
- `Squidie.reject/3` - Reject manual approval steps
- `Squidie.replay/2` - Replay completed workflows
- `Squidie.start/3` - Start a run from a host-provided workflow module
- `Squidie.start_spec/3` - Start a run from a host-provided runtime spec

Host applications still own workers, queue delivery, scheduler
setup, and backend leasing or fencing. When a Squidie host uses Bedrock or
another delivery backend, that adapter remains part of the host application, not
SquidSonar.

```text
Phoenix Host Application
|
+-- Squidie runtime
|   +-- workers
|   +-- scheduler and delivery backend
|   +-- lease or fencing adapter when needed
|
+-- SquidSonar
    +-- router macro
    +-- operator LiveViews
    +-- embedded assets
    +-- Squidie inspection and control API client
```

## Dashboard Surface

The UI includes:

- Recent workflow runs sorted by update time
- Status counts and filters
- Search across workflow, trigger, step, status, and run ID
- Page size controls and pagination
- Run detail pages with diagnosis, history counts, last error, and workflow
  graph visualization
- Recovery metadata on compensatable graph nodes when Squidie exposes
  rollback policy information
- Recovery policy summaries that distinguish declared rollback callbacks,
  non-compensatable steps, and manual-review replay boundaries
- Deadline and escalation evidence when Squidie exposes step SLA state,
  including due-soon, overdue, and escalated run filters
- Step attempt counts on run detail pages
- Light, dark, and system theme controls
- Embedded CSS and JavaScript served by the library

SquidSonar only displays deadline and escalation state returned by Squidie.
Alert delivery, notification routing, paging rules, and escalation side effects
remain host-application responsibilities.

## Requirements

- Elixir 1.17 or later
- Phoenix 1.8
- Phoenix LiveView 1.1
- A host application with Squidie installed and configured

## Installation

Add SquidSonar to the host application's dependencies:

```elixir
def deps do
  [
    {:squid_sonar, "~> 0.2.0"}
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
  control_actor: {MyAppWeb.SquidSonarAudit, :control_actor, []},
  runtime_specs: {MyAppWeb.SquidSonarRuntimeSpec, :runtime_specs, []},
  action_registry: {MyAppWeb.SquidSonarRuntimeSpec, :action_registry, []}
```

`transport` can be `"websocket"` or `"longpoll"`.

`control_actor` is persisted with Squidie manual actions such as resume,
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

`runtime_specs` and `action_registry` enable a start drawer on the `/sonar`
dashboard. `runtime_specs` is a host-approved catalog of workflows that an
operator may start. Pass a keyword list or map of stable keys to Squidie DSL
workflow modules or runtime specs, or pass an MFA tuple that receives the
current `Plug.Conn` as its first argument:

```elixir
defmodule MyAppWeb.SquidSonarRuntimeSpec do
  def runtime_specs(_conn) do
    [
      checkout: MyApp.Workflows.Checkout,
      invoice_reconciliation: MyApp.Workflows.InvoiceReconciliation
    ]
  end
end
```

The drawer lists those configured workflows, prepopulates payload JSON from the
selected workflow's payload contract, and starts the selected host-approved
workflow with that payload. The browser submits only the selected catalog key
plus payload JSON; SquidSonar looks up the entry server-side. DSL workflow
module entries start through `Squidie.start/3`. Runtime-authored spec entries
start through `Squidie.start_spec/3`.

This is not a full workflow JSON editor. If operators need arbitrary workflow
JSON, the host app should first validate and approve that JSON into a runtime
spec catalog entry and action registry. The action registry is the trust
boundary for runtime-authored specs: specs should reference stable action keys,
and the host maps those keys to approved Squidie/Jido action modules before
`Squidie.start_spec/3` runs. DSL workflow modules do not need action keys for
their own steps. `runtime_spec` remains supported as a single-spec compatibility
option, but new integrations should prefer `runtime_specs`.

Do not put secrets or tenant-private data in the runtime spec or action
registry. These values are part of the signed LiveView session used to boot the
embedded UI.

Runtime-spec starts are activation-only in SquidSonar. Squidie persists enough
definition data for inspection, but replay of runtime-spec runs is not
supported. DSL workflow module entries use Squidie's normal workflow start path.

`saved_specs` is the read-only inspection surface for host-provided workflow
spec records. It complements runtime execution: `runtime_specs` answers "what
can this operator start now?", while `saved_specs` answers "what spec did the
host save, is it valid, what changed from the source spec, and is it approved to
start?" This matters for runtime-authored workflows, visual-editor JSON, or
host approval flows where the spec exists outside compiled Elixir modules.

SquidSonar does not create saved specs. The host app can provide records derived
from an Elixir DSL workflow, persisted editor JSON, a stored runtime-authored
spec, or an approval workflow that has already converted editor JSON into an
executable runtime spec. SquidSonar only lists, validates, previews, diffs, and
optionally starts approved records.

Mounting `saved_specs` exposes those records under `/sonar/saved-specs/:key` and
adds a saved-spec list to the dashboard. Pass a keyword list or map of stable
keys to saved-spec metadata, or an MFA tuple that receives the current
`Plug.Conn`:

```elixir
defmodule MyAppWeb.SquidSonarRuntimeSpec do
  def saved_specs(_conn) do
    [
      checkout_runtime_spec: %{
        title: "Checkout runtime spec",
        status: :approved,
        editor_json: checkout_editor_json(),
        source_spec: current_checkout_editor_json(),
        spec: approved_checkout_runtime_spec()
      }
    ]
  end
end
```

The detail page validates `editor_json`, shows structured validation errors,
renders the preview graph and raw JSON, and shows a diff when `source_spec` is
present. `status: :approved` plus `spec` enables the start form, which reuses
the same runtime-spec start boundary as the dashboard drawer. The host app still
owns persistence, approval policy, action registry lookup, activation rules, and
any conversion from editor JSON into an executable runtime spec. SquidSonar does
not save specs, approve specs, or convert unapproved browser-submitted JSON
into runtime definitions.

## Security

SquidSonar does not ship its own authentication layer. Protect the mounted route
with the same browser pipeline, session handling, and authorization rules used
for the rest of the host application's operator surface.

The dashboard can issue Squidie control actions when a run exposes safe
manual actions. It also displays runtime data returned by Squidie, including
workflow names, run IDs, step names, statuses, diagnostic signals, and selected
error metadata. Treat the mounted dashboard as an operational control surface
and expose it only to trusted users.

Run list and run detail pages refresh automatically while they are open. Detail
pages poll active runs and run list pages reload the current filtered view, so
manual controls can reflect follow-up workflow work without a browser refresh.

## Example App

The repository includes a Phoenix example app at `examples/example_app`. It
mounts SquidSonar at `/sonar` and seeds real Squidie workflows that produce
completed, failed, retrying, paused, approval-paused, and saga recovery runs.
It also configures a host-owned runtime-spec catalog exposed from the `/sonar`
dashboard drawer.
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
- `SquidSonar.Runs` is the read boundary over Squidie run APIs.
- `SquidSonar.Dashboard` builds the filtered, paginated dashboard snapshot.
- `SquidSonar.Runs.WorkflowGraph` turns workflow definitions and persisted run
  state into a display graph.
- `SquidSonarWeb.*` contains the embedded LiveViews, components, layout, hooks,
  and asset controller.

## Community

Use the [Squidie Elixir Forum thread](https://elixirforum.com/t/squidie-workflow-automation-runtime-for-elixir-applications/75162)
for public discussion and design context around the runtime and dashboard.

Use [GitHub issues](https://github.com/dark-trench/squid_sonar/issues) for
dashboard bugs, feature requests, and release-tracked work.

For informal runtime and Jido-adjacent chat, use the
[Squidie channel on the Jido Discord](https://discord.com/channels/1323353012235796550/1504122798027571331).

## License

Apache-2.0
