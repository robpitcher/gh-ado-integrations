# Copilot instructions — Contoso Logistics

Contoso Logistics has two connected parts in one repo: a small Express shipment app and an Azure DevOps + GitHub Actions release-tracking lab. Keep changes simple, dependency-light, and consistent with existing CommonJS style.

## Build, test, and lint commands

| Task | Command | Notes |
|---|---|---|
| Install deps | `npm ci` | Use Node 20+ (`package.json` engines). |
| Run app | `npm start` | Serves `http://localhost:3000` from `src/server.js`. |
| Dev mode | `npm run dev` | Uses `node --watch src/server.js`. |
| Full tests | `npm test` | Runs Jest in-band (`jest --runInBand`). |
| Single test file | `npx jest test/shipments.test.js --runInBand` | Replace with any file under `test/`. |
| Single test case | `npx jest test/shipments.test.js -t "GET /api/health returns ok" --runInBand` | Use `-t` with a test name substring. |

There is no repo lint script in `package.json`. If you edit GitHub workflows, run `actionlint` locally.

## High-level architecture

### Runtime app path
- `src/server.js` starts `createApp()` from `src/app.js`.
- `src/app.js` wires JSON parsing, `/api/shipments`, `/api/carriers`, static `public/`, and one centralized error handler (`err.statusCode || 500`).
- Route handlers in `src/routes/*.js` orchestrate request/response only; domain logic lives in `src/services/*.js`.
- State is in-memory seed data from `src/data/*.js` (no DB layer). For example, shipment event POSTs mutate shipment objects directly via `appendEvent`.
- `public/app.js` is a no-build vanilla JS client that calls the REST endpoints and renders list/detail/timeline views.

### Release-tracking path (lab automation)
- Every push to `main` runs `deploy.yml`, resolves release `version` from `package.json`, and deploys `dev -> stage -> production`.
- `ado-release-sync.yml` (reusable workflow) computes release membership from semver tag range `<previous_tag>..HEAD`, extracts `AB#` references from commits, links stories to the Release work item, and stamps `Custom.ShippedRelease`.
- `ado-release-complete.yml` runs only after successful production deployment, closes linked stories, closes/stamps the Release item, and publishes the GitHub Release/tag that becomes the next lower bound.
- `provision/*.ps1` scripts create and verify the ADO lab setup; these are idempotent PowerShell 7 scripts authenticated via `az login`.

## Key conventions

- Use CommonJS (`require`/`module.exports`) and `'use strict';` in JS files.
- Prefer route/service split: keep business rules in `src/services`, not in routers.
- Raise service errors with `statusCode` so they flow through the centralized API error handler.
- Keep persistence in-memory: mutate `src/data` structures rather than introducing a datastore.
- Treat `TODO (story ...)` functions in services as intentional extension points mapped to Azure Boards work.
- Release boundaries are **tags, not branches**; do not reintroduce `release/**` or `origin/main..HEAD` logic.
- `package.json` `version` is the release selector (`Custom.ReleaseVersion`) and published tag/release name; keep it synchronized with `package-lock.json`.
- Only semver-shaped tags (`^v?\d+\.\d+\.\d+$`) are valid boundaries; keep regex logic aligned between `ado-release-sync.yml` and `provision/11-ReleaseBaseline.ps1`.
- Production approval is enforced by the `production` GitHub Environment, not by workflow conditionals.
- Release-to-story links must be `System.LinkTypes.Related` (never hierarchy links).
- Work-tracking automation must not fail deployments: use step-level `continue-on-error` inside reusable workflows; do not set `continue-on-error` on `uses:` jobs.
- Keep `AB#` references in merge-surviving text (PR title is preferred) so release sync can derive membership from commit history.
- `docs/release-automation-guide.md` should reference workflow files by relative path and avoid embedding full workflow YAML.
- `.github/workflows/*.yml` remains the authoritative source for workflow definitions.
