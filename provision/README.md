# Provision — Azure DevOps lab provisioner (PowerShell)

PowerShell 7 scripts that build the **Contoso Logistics** Azure DevOps demo environment from
scratch, with no PAT (they use your `az login` AAD token). For environment setup and operations,
see the [`administrator lab guide`](../docs/user-lab-guide.md). For the presenter walkthrough and
evaluation steps, see the [`demo lab guide`](../docs/demo-lab-guide.md).

## Quick start

```powershell
az login                                   # account that owns the ADO org
cd provision
./Provision.ps1 -OrgName <your-org>
./Verify.ps1   -OrgName <your-org>
```

> `-OrgName` takes just the org **name** (e.g. `myorg`). A full URL
> (`https://dev.azure.com/myorg`) still works too.

## Parameters (Provision.ps1)

| Param | Default | Purpose |
|---|---|---|
| `-OrgName` (alias `-Org`, `-OrgUrl`) | *(required)* | Your ADO org name, e.g. `myorg` (or a full URL `https://dev.azure.com/myorg`) |
| `-Project` | `Contoso Logistics` | Project name to create/use |
| `-Force` | off | Recreate the project if it's on a different process (⚠️ destructive) |
| `-IncludePipeline` | off | Also run the optional ADO pipeline step |
| `-IncludeGitHub` | off | Also provision GitHub Environments (`dev`/`stage`/`production`) and the baseline release tag |
| `-GitHubRepo` | — | Required with `-IncludePipeline` or `-IncludeGitHub`, e.g. `you/contoso-logistics` |

Config can also come from env vars `ADO_ORG_NAME` (or legacy `ADO_ORG_URL`) / `ADO_PROJECT`
when running steps individually. The org value accepts a bare name or a full URL, same as `-OrgName`.

## Scripts

| Script | Creates |
|---|---|
| `Common.ps1` | Shared auth + REST helpers (dot-sourced by each step) |
| `01-Process.ps1` | Inherited process **Contoso Agile**; User Story state **Ready for Release** in the Resolved category; `Custom.TargetRelease` (text) + `Custom.ShippedRelease` (text); the custom **Release** work item type |
| `02-Project.ps1` | The project on the Contoso Agile process |
| `03-Structure.ps1` | **App Team**, **QA Team**, **DevOps Team**; area paths; 3 sprints |
| `04-WorkItems.ps1` | 3 Epics (Logistics × 2 + DevOps), 9 Features, 34 User Stories + cross-sprint dependencies; sets `Custom.TargetRelease` per sprint; `-ResetStates` restores seeded states **and** `Custom.TargetRelease` |
| `09-Releases.ps1` | 3 **Release** work items (`1.0.0`/`1.1.0`/`1.2.0`) as empty containers; `-Reset` restores the whole release-tracking baseline (see below) |
| `05-Views.ps1` | Project-scoped queries (incl. Ready for Release, Release Contents/Drift, Targeted-Not-Yet-Shipped, Shipped but Not Closed, Release Register) + Contoso Delivery dashboard |
| `06-Layout.ps1` | Adds **Target Release** + **Shipped Release** to the User Story form's Delivery group (per-control idempotent — see gotchas) |
| `07-Plans.ps1` | Contoso Roadmap Delivery Plan (App + QA + DevOps, story level) |
| `08-Pipeline.ps1` | *(optional)* GitHub service connection + CI pipeline (`gh auth token`) |
| `10-GitHubEnvironments.ps1` | *(optional)* GitHub Environments `dev`/`stage`/`production`, with a required reviewer + `main` branch policy on `production` (`gh auth token`) |
| `11-ReleaseBaseline.ps1` | *(optional)* The **baseline git tag** (`0.9.0` by default; `v0.9.0` also valid) that bounds the first release. `-Force` moves it to current `main` — the between-demo reset; `-Delete` removes it (`gh auth token`) |
| `New-DemoPullRequest.ps1` | Fills a release the way it happens for real: one branch, change, commit (**no** `AB#`) and pull request (`Ready for Release AB#<id>` in the description) per targeted story, optionally squash-merged. Works in a temp clone |
| `Get-DemoCommits.ps1` | Offline shortcut: prints ready-to-paste commits with `Ready for Release AB#<id>` in each message. Skips the PR/check/merge — prefer `New-DemoPullRequest.ps1` |
| `Provision.ps1` | Orchestrates 01→04→09→05→06→07 (+08 with `-IncludePipeline`, +10 and 11 with `-IncludeGitHub`) |
| `Verify.ps1` | Pass/fail health check of the whole environment (pass `-GitHubRepo` to also check GitHub Environments) |

Each `NN-*.ps1` is also runnable on its own (e.g. `./05-Views.ps1 -OrgName myorg`).

### Resetting the release-tracking baseline

Between demo runs:

```powershell
./09-Releases.ps1        -OrgName myorg -Reset
./11-ReleaseBaseline.ps1 -GitHubRepo you/contoso-logistics -Force
```

The first removes every Release↔Story link, clears `Custom.ShippedRelease`, resets each Release work
item to `New` (clearing its deploy metadata), and calls `04-WorkItems.ps1 -ResetStates` to put
seeded stories back in their original states. It does **not** touch GitHub.

The second re-points the baseline tag at whatever `main` is now, so the next release's commit range
starts from a clean slate — **`main` is never rewritten or force-pushed.** Delete the GitHub Release
for the version you just shipped separately (`gh release delete 1.0.0 --cleanup-tag`), and reset
`version` in `package.json` if you bumped it (see the reset section in
[`../docs/user-lab-guide.md`](../docs/user-lab-guide.md)).

> `11-ReleaseBaseline.ps1` expects named arguments (for example `-GitHubRepo owner/repo`); if a repo
> is accidentally passed as `-Tag`, the script now fails with an explicit guidance message.

## Notes / gotchas (baked into the scripts)

- **Contoso Agile is intentionally lightly customized.** It is an inherited copy of the built-in Agile
  process, plus Ready for Release and the release-tracking fields/WIT described above. Add further states, fields,
  and rules via **Org Settings → Process → Contoso Agile** in the ADO UI, or extend `01-Process.ps1`.
- **Idempotent migration:** `03-Structure.ps1` renames a legacy `Dev Team` → `App Team` and the
  `Dev` area → `App` when re-run on an older environment, instead of creating duplicates.
- **Story state categories** remain Azure DevOps defaults:
  `Proposed → InProgress → Resolved → Completed → Removed`. The custom
  `Ready for Release` state belongs to `Resolved`, producing the demo lifecycle
  `Active → Ready for Release → Closed`.
- **System work item types must be *derived*** (`inheritsFrom`) before adding states/fields/rules.
  A brand-new custom type (like **Release**) must instead be created **without** `inheritsFrom` —
  that omission is what makes it a genuinely new type rather than a derived system type.
- **Releases are bounded by git tags, not branches.** There is no `release/**` branch: story PRs
  merge into `main`, and `ado-release-sync.yml` defines a release's contents as
  `<previous release tag>..HEAD`. The tag is written by automation when the previous release
  completes, so each release automatically bounds the next one. `11-ReleaseBaseline.ps1` seeds the
  very first lower bound.
- **`version` in `package.json` selects the pending Release work item.** It is matched against
  `Custom.ReleaseVersion`, is the name of the GitHub Release/tag that gets published, and bumping it
  in a PR is the single human act that opens the next release. Once a release is `Closed`, further
  sync runs refuse to add work and prompt for a version bump — that is deliberate, not a bug.
- **`Release` is deliberately not on any backlog level.** A work item can only have one parent, and
  stories already parent to Features — adding Release to a backlog would let it compete for that
  parent slot. The Release↔Story relationship is always `System.LinkTypes.Related` (many-to-many),
  never a hierarchy/child link.
- **WIQL cannot compare two fields to each other.** Drift queries (`Custom.TargetRelease` vs.
  `Custom.ShippedRelease`) must pin one side to a literal per release; true cross-field drift
  reporting lives in the `ado-release-sync.yml` job summary instead.
- **`06-Layout.ps1` checks for missing form controls per control, not all-or-nothing** — a form
  that already has one of two target controls must still get the other added, not be skipped.
- **Relation removal is by index, in descending order** — removing a lower index first would shift
  the indices of the relations after it (`09-Releases.ps1 -Reset` depends on this).
- **State `order` is omitted** — ADO auto-places states; explicit values collide with system states.
- **Release selector fields are plain text, not picklists** — new release versions do not require a
  process migration.
- **The Release Version required rule is always on** — it uses an `isEnabled` condition with a
  `makeRequired` action.
- **Work items are created in `New`, then PATCHed** to the target state.
- **Pie chart widget** needs `measure` as an object `{aggregation:'count',propertyName:''}`,
  `chartType:'PieChart'`, `scope:'WorkitemTracking.Queries'`.
- **All queries are project-scoped** with `[System.TeamProject]` to avoid pulling other projects' data.
- **Required reviewers on GitHub Environments need a paid plan tier on private repos** —
  `10-GitHubEnvironments.ps1` catches that failure and creates the environment ungated rather than
  erroring the whole provisioning run.
- Project `properties` and dashboard/pipeline/service-endpoint endpoints use `-preview` api-versions.

Requires **PowerShell 7+**.
