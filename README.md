# Contoso Logistics

A small demo web app for **shipment tracking** and **warehouse operations**, used to showcase
end-to-end delivery in Azure DevOps + GitHub (boards, repos, CI, and the GitHub Copilot coding
agent) with fictional sample data.

> [!IMPORTANT]
> This repository is a proof of concept and learning lab. It is not production-ready or intended
> for direct production use; review and adapt its identity, secrets, permissions, deployment,
> resilience, and operational controls before applying any pattern to a real system.

## Stack
- **Backend:** Node.js + Express, in-memory data (no database)
- **Frontend:** vanilla JS + CSS (no framework, no build step)
- **Tests:** Jest + supertest
- **CI:** GitHub Actions (`.github/workflows/ci.yml`) runs `npm test` on every PR

## Azure DevOps lab

This repo doubles as a **hands-on Azure DevOps lab**. The `provision/` folder has PowerShell
scripts that build a complete ADO demo environment (inherited process ready to customize, work
items for app dev + DevOps, sprints, queries, dashboard, Delivery Plan, and an optional CI
pipeline) pointed at your own org — no PAT required for provisioning. Fork the repo, then:

```powershell
az login
cd provision
./Provision.ps1 -OrgUrl https://dev.azure.com/<your-org> -Project ProjectName
./Verify.ps1   -OrgUrl https://dev.azure.com/<your-org> -Project ProjectName
```

Environment setup and operations: **[administrator lab guide](docs/user-lab-guide.md)** ·
presenter walkthrough: **[demo lab guide](docs/demo-lab-guide.md)** · provisioner reference:
**[provision/README.md](provision/README.md)**.

### Release tracking scenario

On top of the base lab, this repo also demonstrates **release tracking across Azure DevOps and
GitHub Actions**: story pull requests merge into `main`, and each release is
defined as the span of commits **between two git tags** — so release membership is derived from what
actually shipped, with no manual relate step. Every push to `main` runs a gated multi-environment
deploy (`dev` → `stage` → `production`), and a successful, approved production deploy automatically
closes out the linked work items, publishes GitHub Release notes, and writes the tag that bounds the
*next* release. The presenter walkthrough is driven by a real work item taken end to end — assigned, implemented,
pull-requested, merged, deployed — rather than synthetic commits. See the **Release tracking**
section of the [demo lab guide](docs/demo-lab-guide.md). For environment setup and ongoing
operation, use the [administrator lab guide](docs/user-lab-guide.md). Relevant workflows:
`.github/workflows/deploy.yml`, `ado-release-sync.yml`, `ado-release-complete.yml`, and
`pr-workitem-check.yml` (which checks the PR title, body, commits, and comments; release membership
still requires the `AB#` reference to reach commit history).


## Quick start
```bash
npm ci
npm start        # http://localhost:3000
npm test         # run the test suite
npm run dev      # auto-restart on change
```

## API
| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Health check |
| GET | `/api/shipments` | List shipments (summary) |
| GET | `/api/shipments/:id` | Shipment detail + carrier + delivery window |
| GET | `/api/shipments/:id/events` | Ordered status timeline |
| POST | `/api/shipments/:id/events` | Record a status change `{ status, note }` |
| GET | `/api/carriers` | Carrier directory |
| GET | `/api/carriers/:id` | Single carrier |

## Roadmap (maps to Azure Boards)

This repo is paired with the **Contoso Logistics** Azure DevOps project. The project has three
teams — **App Team** (application development), **QA Team** (quality), and **DevOps Team**
(platform engineering). Implemented features correspond to completed stories; the stubbed service
functions (marked `TODO (story ...)`) correspond to open backlog items and are ready to be picked
up — by a teammate or the GitHub Copilot coding agent assigned from a work item.

**Implemented**
- Shipment list, live location, and status timeline
- Estimated delivery window
- Carrier webhook normalization
- Optimal-bin suggestion for putaway

**Open extension points** (App Team backlog)
- Customer notifications: out-for-delivery email, SMS opt-in/preferences, audit log
- Carrier integrations: failed-callback retry, SLA dashboard feed
- Warehouse: nightly reslotting of slow movers, batch picking by zone

**DevOps Team backlog** (platform & infrastructure stories seeded in the ADO project)
- CI/CD: blue/green release, deploy-to-staging automation
- Infrastructure as Code: container image, environment provisioning, secrets management
- Observability: distributed tracing, health-check alerts
- Security: SBOM generation, base-image hardening

See `.github/copilot-instructions.md` for conventions and how changes are verified.

## License
MIT
