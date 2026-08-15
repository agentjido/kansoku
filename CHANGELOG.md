# Changelog

All notable changes to Kansoku will be documented in this file.

## Unreleased

- Renamed the package, OTP application, module namespace, router macro, assets,
  UI hooks, example application, and documentation from SquidSonar to Kansoku.
- Replaced the Squidie client boundary with Jizoku. This is an explicit
  breaking cutover with no compatibility namespace or configuration fallback.

## 0.3.0 - 2026-07-13

- Added shareable dashboard filters, safe run-ID prefix navigation, shared
  operator navigation, visible-value copy controls, and a read-only settings
  page with an allowlisted runtime projection.
- Added read-only operator queues for active manual boundaries and cron
  triggers declared by host-approved workflow specs.
- Added actor-scoped Squidie visibility policy configuration for queue reads.
- Upgraded Squidie to `0.3.4`.

## 0.2.0 - 2026-06-15

- Added dashboard support for runtime spec starts, saved workflow spec drafts,
  live claims, deferred continuations, dynamic work overlays, compensation
  evidence, and recovery policy diagnostics.
- Added workflow control operations and the raw workflow inspection tab for run
  detail pages.
- Rebranded Squid Mesh references to Squidie across the public package surface
  and example application.
- Upgraded Squidie to `0.3.0` and aligned the example app dependency lockfile
  with the new runtime dependency set.
- Upgraded Phoenix LiveView to `1.2.1` and split repeated UI event names so the
  strict quality gates stay green.
- Added strict CI quality gates and updated development, documentation, and
  security dependencies.
- Updated package metadata and install snippets to reference `0.2.0`.

## 0.1.7 - 2026-05-26

- Clarified the README runtime boundary around SquidSonar's read-only Squid
  Mesh API usage.
- Documented that host applications still own workers, scheduling, delivery
  backends, and lease or fencing adapters.
- Removed stale `otp_app` router usage from README and module documentation
  examples.
- Aligned the README header format with the Squidie package README.
- Updated package metadata and install snippets to reference `0.1.7`.

## 0.1.6 - 2026-05-25

- Added regression coverage for Discord notification payload formatting.
- Fixed Discord notification workflow output so multiline messages use real
  newlines instead of escaped newline text.
- Moved README community links into a dedicated Community section.
- Updated install snippets to reference `0.1.6`.

## 0.1.5 - 2026-05-24

- Added the journal-aware workflow graph header status and shared read-model
  fixtures from the SquidSonar review pass.
- Kept the example seed output focused on completed, failed, retrying, and
  paused runs.
- Removed stale lockfile entries so dependency checks stay green.

## 0.1.4 - 2026-05-24

- Aligned the example app seed with the journal-backed runtime so the seeded
  demo shows completed, failed, retrying, and paused runs.
- Kept the release focused on the journal runtime contract and example
  coverage.

## 0.1.3 - 2026-05-16

- Refined status badge styling with rectangular labels.
- Aligned status filter hover and focus states with the runs table interaction.
- Removed the redundant matching-run summary from the status filter sidebar.

## 0.1.2 - 2026-05-16

- Refined the embedded dashboard with a cleaner, flatter visual system.
- Added a responsive filter menu for smaller screens.
- Improved status filter active states, table controls, run detail surfaces, and
  workflow canvas contrast.

## 0.1.1 - 2026-05-15

- Added visible refresh feedback while dashboard runs reload.

## 0.1.0 - 2026-05-15

- Added the embeddable Phoenix LiveView dashboard for Squidie runs.
- Added status filters, search, pagination, run detail pages, workflow graph
  visualization, attempt counts, and light/dark/system themes.
- Added a Phoenix example app with real Squidie workflow scenarios.
- Added public-facing repository documentation, templates, license, and CI
  metadata.
