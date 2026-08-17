# Kansoku

<div align="left">
  <p>
    <a href="https://github.com/dark-trench/kansoku/actions/workflows/ci.yml">
      <img alt="CI" src="https://github.com/dark-trench/kansoku/actions/workflows/ci.yml/badge.svg" />
    </a>
    <a href="https://hex.pm/packages/kansoku">
      <img alt="Hex" src="https://img.shields.io/hexpm/v/kansoku" />
    </a>
    <a href="https://hexdocs.pm/kansoku">
      <img alt="HexDocs" src="https://img.shields.io/badge/docs-hexdocs-purple" />
    </a>
    <a href="https://github.com/dark-trench/kansoku/blob/main/LICENSE">
      <img alt="License: Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" />
    </a>
  </p>
</div>

Kansoku is an embeddable Phoenix LiveView operator dashboard for
applications that run Jizoku workflows.

The name “Kansoku” (観測) comes from the Japanese word meaning “observation” or
“measurement.” It reflects the dashboard's role: giving operators a clear view
into Jizoku workflows, their state, history, failures, and recovery.

Mount it inside a Phoenix host application to inspect recent runs, filter by
status, search runtime metadata, and open detail pages with the workflow graph,
diagnosis, attempt counts, history counts, and last error information. It also
exposes Jizoku control operations such as cancel, resume, approval, rejection,
replay, and runtime-spec starts when the host application wires the required
operator context.

## Runtime Boundary

Kansoku is distributed as an embeddable library, not a standalone service. A
host Phoenix application owns authentication, authorization, deployment,
endpoint configuration, and the Jizoku runtime. Kansoku contributes the
router macro, LiveViews, static assets, and a bounded operator surface over
Jizoku public APIs.

Kansoku interacts with Jizoku through:

### Read Operations
- `Jizoku.list_runs/2`
- `Jizoku.inspect_run/2`
- `Jizoku.inspect_run_graph/2`
- `Jizoku.explain_run/2`

### Control Operations
- `Jizoku.cancel/2` - Cancel running workflows
- `Jizoku.resume/3` - Resume paused workflows
- `Jizoku.approve/3` - Approve manual approval steps
- `Jizoku.reject/3` - Reject manual approval steps
- `Jizoku.replay/2` - Replay completed workflows
- `Jizoku.start/3` - Start a run from a host-provided workflow module
- `Jizoku.start_spec/3` - Start a run from a host-provided runtime spec

Host applications still own workers, queue delivery, scheduler
setup, and backend leasing or fencing. When a Jizoku host uses Bedrock or
another delivery backend, that adapter remains part of the host application, not
Kansoku.

```text
Phoenix Host Application
|
+-- Jizoku runtime
|   +-- workers
|   +-- scheduler and delivery backend
|   +-- lease or fencing adapter when needed
|
+-- Kansoku
    +-- router macro
    +-- operator LiveViews
    +-- embedded assets
    +-- Jizoku inspection and control API client
```

## Dashboard Surface

The UI includes:

- Recent workflow runs sorted by update time
- Status counts and filters
- Shareable URL filters for workflow, status, terminal state, queue, time window,
  run ID prefix, deadline state, and pending manual actions
- Direct navigation by an exact or unambiguous run ID prefix
- Shared navigation for recent runs, workflows, manual actions, and read-only
  runtime settings
- Copy controls for visible run identifiers and safely projected settings JSON
- Search across workflow, trigger, step, status, and run ID
- Page size controls and pagination
- Run detail pages with diagnosis, history counts, last error, and workflow
  graph visualization
- A read-only operator queue for active manual boundaries and cron triggers
  declared by host-approved workflow specs
- Recovery metadata on compensatable graph nodes when Jizoku exposes
  rollback policy information
- Recovery policy summaries that distinguish declared rollback callbacks,
  non-compensatable steps, and manual-review replay boundaries
- Deadline and escalation evidence when Jizoku exposes step SLA state,
  including due-soon, overdue, and escalated run filters
- Step attempt counts on run detail pages
- Light, dark, and system theme controls
- Embedded CSS and JavaScript served by the library

Kansoku only displays deadline and escalation state returned by Jizoku.
Alert delivery, notification routing, paging rules, and escalation side effects
remain host-application responsibilities.

## Requirements

- Elixir 1.17 or later
- Phoenix 1.8
- Phoenix LiveView 1.1
- A host application with Jizoku installed and configured

## Installation

Add Kansoku to the host application's dependencies:

```elixir
def deps do
  [
    {:kansoku, "~> 0.4.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

Kansoku 0.4.0 is a breaking package and namespace rename. Existing
applications can remain pinned to earlier releases until an operator chooses a
cutover window. See the [migration guide](MIGRATION.md).

## Mounting

Import `Kansoku.Router` in the host router and mount the dashboard under the
path that makes sense for the application:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use Kansoku.Router

  scope "/ops" do
    pipe_through [:browser, :require_authenticated_user]

    kansoku "/kansoku"
  end
end
```

Visit `/ops/kansoku` to open the dashboard.

Kansoku accepts a few route-level options:

```elixir
kansoku "/kansoku",
  as: :runtime_kansoku,
  socket_path: "/live",
  transport: "websocket",
  control_actor: {MyAppWeb.KansokuAudit, :control_actor, []},
  visibility_actor: {MyAppWeb.KansokuAudit, :visibility_actor, []},
  visibility_policy: MyApp.JizokuVisibilityPolicy,
  runtime_specs: {MyAppWeb.KansokuRuntimeSpec, :runtime_specs, []},
  action_registry: {MyAppWeb.KansokuRuntimeSpec, :action_registry, []}
```

`transport` can be `"websocket"` or `"longpoll"`.

`control_actor` is persisted with Jizoku manual actions such as resume,
approve, and reject. It can be a non-empty string, a non-empty map, or an MFA
tuple. MFA callbacks receive the current `Plug.Conn` as their first argument.
Prefer a small audit map over a raw user struct:

```elixir
defmodule MyAppWeb.KansokuAudit do
  def control_actor(conn) do
    user = conn.assigns.current_user

    %{
      "type" => "user",
      "id" => user.id
    }
  end

  def visibility_actor(conn) do
    conn.assigns.current_user.id |> to_string()
  end
end
```

If omitted, Kansoku uses a placeholder actor so local demos can exercise
manual controls. Production mounts should pass the authenticated operator once
the host app wires Kansoku into its own auth pipeline.

`visibility_actor` and `visibility_policy` are applied before Kansoku
projects manual-queue and run-detail data. The actor must be a minimal opaque
identifier or an MFA returning one; it defaults to the resolved control actor's
`id`. LiveView session values are signed but not encrypted, so never return
secrets, personal data, role claims, or full user structs from this callback.

The policy accepts Jizoku's `:external`, `:operator`, or `:auditor` scope, a
policy module, or `{module, opts}`; it defaults to `:operator`. Module policies
receive the opaque identifier on every read and should fetch current
server-side authorization state, failing closed for revoked or missing actors.
Run mutation controls are available only for the `:operator` policy and still
depend on the host application's authenticated and authorized router pipeline.
The `:auditor` and `:external` policies are read-only.

Visit `/kansoku/queues` to review all currently paused manual boundaries and cron
triggers declared by `runtime_specs`. Scheduler enablement, future windows, and
activation delivery remain host-owned and are not inferred by Kansoku.

Visit `/kansoku/settings` to inspect a read-only, allowlisted runtime projection.
It reports package versions, transport and access labels, and catalog counts;
actors, policy options, registry contents, modules, paths, and host configuration
values are never rendered.

`runtime_specs` and `action_registry` enable a start drawer on the `/kansoku`
dashboard. `runtime_specs` is a host-approved catalog of workflows that an
operator may start. Pass a keyword list or map of stable keys to Jizoku DSL
workflow modules or runtime specs, or pass an MFA tuple that receives the
current `Plug.Conn` as its first argument:

```elixir
defmodule MyAppWeb.KansokuRuntimeSpec do
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
plus payload JSON; Kansoku looks up the entry server-side. DSL workflow
module entries start through `Jizoku.start/3`. Runtime-authored spec entries
start through `Jizoku.start_spec/3`.

This is not a full workflow JSON editor. If operators need arbitrary workflow
JSON, the host app should first validate and approve that JSON into a runtime
spec catalog entry and action registry. The action registry is the trust
boundary for runtime-authored specs: specs should reference stable action keys,
and the host maps those keys to approved Jizoku/Jido action modules before
`Jizoku.start_spec/3` runs. DSL workflow modules do not need action keys for
their own steps. `runtime_spec` remains supported as a single-spec compatibility
option, but new integrations should prefer `runtime_specs`.

Do not put secrets or tenant-private data in the runtime spec, action registry,
or saved-spec records. These values are part of the signed, client-readable
LiveView session used to boot the embedded UI. Keep credentials and private
action options in server-side runtime configuration.

Runtime-spec starts are activation-only in Kansoku. Jizoku persists enough
definition data for inspection, but replay of runtime-spec runs is not
supported. DSL workflow module entries use Jizoku's normal workflow start path.

`saved_specs` is the read-only inspection surface for host-provided workflow
spec records. It complements runtime execution: `runtime_specs` answers "what
can this operator start now?", while `saved_specs` answers "what spec did the
host save, is it valid, what changed from the source spec, and is it approved to
start?" This matters for runtime-authored workflows, visual-editor JSON, or
host approval flows where the spec exists outside compiled Elixir modules.

Kansoku does not create saved specs. The host app can provide records derived
from an Elixir DSL workflow, persisted editor JSON, a stored runtime-authored
spec, or an approval workflow that has already converted editor JSON into an
executable runtime spec. Kansoku only lists, validates, previews, diffs, and
optionally starts approved records.

Mounting `saved_specs` exposes those records under `/kansoku/saved-specs/:key` and
adds a saved-spec list to the dashboard. Pass a keyword list or map of stable
keys to saved-spec metadata, or an MFA tuple that receives the current
`Plug.Conn`:

```elixir
defmodule MyAppWeb.KansokuRuntimeSpec do
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
any conversion from editor JSON into an executable runtime spec. Kansoku does
not save specs, approve specs, or convert unapproved browser-submitted JSON
into runtime definitions.

## Security

Kansoku does not ship its own authentication layer. Protect the mounted route
with the same browser pipeline, session handling, and authorization rules used
for the rest of the host application's operator surface.

The dashboard can issue Jizoku control actions when a run exposes safe
manual actions. It also displays runtime data returned by Jizoku, including
workflow names, run IDs, step names, statuses, diagnostic signals, and selected
error metadata. Treat the mounted dashboard as an operational control surface
and expose it only to trusted users.

Run list and run detail pages refresh automatically while they are open. Detail
pages poll active runs and run list pages reload the current filtered view, so
manual controls can reflect follow-up workflow work without a browser refresh.

## Example App

The repository includes a Phoenix example app at `examples/example_app`. It
mounts Kansoku at `/kansoku` and seeds real Jizoku workflows that produce
completed, failed, retrying, paused, approval-paused, and saga recovery runs.
It also configures a host-owned runtime-spec catalog exposed from the `/kansoku`
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

Open `http://localhost:4000/kansoku` after the server starts.

## Library Modules

- `Kansoku.Router` mounts the embedded dashboard routes.
- `Kansoku.Runs` is the read boundary over Jizoku run APIs.
- `Kansoku.Dashboard` builds the filtered, paginated dashboard snapshot.
- `Kansoku.Runs.WorkflowGraph` turns workflow definitions and persisted run
  state into a display graph.
- `KansokuWeb.*` contains the embedded LiveViews, components, layout, hooks,
  and asset controller.

## Community

Use the [Jizoku Elixir Forum thread](https://elixirforum.com/t/jizoku-workflow-automation-runtime-for-elixir-applications/75162)
for public discussion and design context around the runtime and dashboard.

Use [GitHub issues](https://github.com/tsuranari/kansoku/issues) for
dashboard bugs, feature requests, and release-tracked work.

For informal runtime and Jido-adjacent chat, use the
[Jizoku channel on the Jido Discord](https://discord.com/channels/1323353012235796550/1504122798027571331).
New members can join through the [Jido Discord invite](https://jido.run/discord).

## License

Apache-2.0
