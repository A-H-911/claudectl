# packages/

This repository is organized as a lightweight monorepo. New, independently-shippable tools live
here as `packages/<name>/`, each self-contained (sources + tests + its own `README.md`).

## Deliberate exception: the `claudectl` CLI stays at the repo root

The primary CLI is **not** under `packages/`. It lives at:

- `scripts/claudectl`, `scripts/claudectl.ps1`, `scripts/claudectl.cmd`
- `setup.sh`, `setup.ps1` (installers)
- `tests/` (its integration suites)

This is intentional. `claudectl`'s self-update endpoint is path-pinned:

```
CLAUDECTL_UPDATE_URL = …/A-H-911/claudectl/main/scripts/claudectl[.ps1]
```

Every already-installed copy has that URL baked in. Moving the script under `packages/` would make
`claudectl setup --update` 404 for those installs (raw.githubusercontent serves no redirects). So the
CLI keeps its stable path, and `packages/` hosts future tools that don't carry that constraint.

## Adding a package

```
packages/<name>/
  <sources>
  tests/
  README.md
```

Keep each package self-contained. Cross-platform parity (bash + PowerShell) and the test-isolation
conventions in [../CLAUDE.md](../CLAUDE.md) apply repo-wide.
