# Changelog

All notable changes to SquidSonar will be documented in this file.

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
