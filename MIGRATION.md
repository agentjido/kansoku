# Migrating to Kansoku

Kansoku is the new name and package identity for the dashboard previously
released as SquidSonar. The change is an explicit, opt-in break. Existing
applications may remain pinned to the old package and release tags until their
operators choose a migration window.

## Rename map

| Previous | New |
| --- | --- |
| Hex dependency `:squid_sonar` | Hex dependency `:kansoku` |
| Module namespaces `SquidSonar` and `SquidSonarWeb` | `Kansoku` and `KansokuWeb` |
| OTP/config application `:squid_sonar` | `:kansoku` |
| Runtime dependency `:squidie` | `:jizoku` |
| Router macro `squid_sonar/1,2` | `kansoku/1,2` |
| Default example path `/sonar` | `/kansoku` |
| Config key `:squidie_client` | `:jizoku_client` |
| Static asset `squid_sonar.css` | `kansoku.css` |

Update dependency declarations, module aliases, router imports and mounts,
configuration, client adapters, hooks, selectors, and tests in one application
release. There are no compatibility aliases or fallback configuration keys.

Kansoku 0.4.0 expects Jizoku 0.4.0 and its fresh persistence schema. Follow the
Jizoku migration guide first, then deploy Kansoku against the new runtime.
Keep the previous dashboard and runtime release available for rollback against
the untouched Squidie schema.
