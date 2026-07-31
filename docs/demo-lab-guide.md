# Contoso Logistics — Azure DevOps Lab Guide

This guide walks you through standing up a complete, hands-on **Azure DevOps** demo/lab
environment from this repo, then evaluating each capability.

By the end you'll have an ADO project that demonstrates:

- An inherited **process** (a clean copy of Agile, ready for you to customize)
- **Portfolio planning** — backlogs, a cross-team Delivery Plan with dependencies, a dashboard
- **Scaling** patterns — three teams (App, QA, DevOps) + area paths over one shared backlog
- **Releases & versioning** — team- and area-scoped queries to slice the backlog
- **Automation** via service hooks (and, optionally, Microsoft Teams)
- *(Optional)* an **Azure Pipeline** that builds & tests the app
- *(Optional)* the **GitHub Copilot coding agent** dispatched from a work item

---

## 1. Prerequisites

| Need | Notes |
|---|---|
| **PowerShell 7+** | `pwsh`. The provisioner scripts target PowerShell 7. |
| **Azure CLI** | `az`. Sign in with `az login` using an account that **owns an Azure DevOps org**. No PAT needed. |
| An **Azure DevOps organization** | e.g. `https://dev.azure.com/<your-org>`. A free org works. |
| *(Optional)* **GitHub CLI** | `gh auth login` — needed for the optional Azure Pipeline and GitHub release-tracking steps. |

> The scripts authenticate with your `az login` AAD token (the Azure DevOps resource id
> `499b84ac-1321-427f-aa17-267ca6975798`). Nothing is stored.

---

## 2. Fork & clone

1. **Fork** this repo to your own GitHub account/org (needed for the optional pipeline + Copilot steps).
2. Clone your fork and open a PowerShell 7 prompt in the repo:
   ```powershell
   git clone https://github.com/<you>/contoso-logistics.git
   cd contoso-logistics
   ```
3. Sign in to Azure CLI with the account that owns your ADO org:
   ```powershell
   az login
   ```

---

## 3. Run the provisioner

From the repo root:

```powershell
cd provision
./Provision.ps1 -OrgUrl https://dev.azure.com/<your-org>
```

This runs steps 01→04→09→05→06→07 and creates everything (idempotent — safe to re-run):

| Step | Creates |
|---|---|
| `01-Process` | Inherited process **Contoso Agile**; also adds `Target Release`/`Shipped Release` fields and the custom **Release** work item type used by the release-tracking scenario (§8) |
| `02-Project` | The **Contoso Logistics** project on that process |
| `03-Structure` | **App Team** + **QA Team** + **DevOps Team**, area paths (`App`/`QA`/`DevOps`), 3 sprints |
| `04-WorkItems` | 3 Epics, 9 Features, 34 User Stories (logistics + DevOps) + cross-sprint dependency links; sets `Target Release` per sprint |
| `09-Releases` | 3 **Release** work items (`1.0.0`/`1.1.0`/`1.2.0`), empty containers — see §8 |
| `05-Views` | Shared queries + the **Contoso Delivery** dashboard (tiles + charts), incl. release-tracking queries |
| `06-Layout` | Adds **Target Release** + **Shipped Release** to the User Story form |
| `07-Plans` | The **Contoso Roadmap** Delivery Plan (stories across sprints, App + QA + DevOps) |

Add `-IncludeGitHub -GitHubRepo <you>/contoso-logistics` to also provision GitHub Environments
(`dev`/`stage`/`production`) and the baseline release tag for the release-tracking scenario in §8.

Confirm everything landed:

```powershell
./Verify.ps1 -OrgUrl https://dev.azure.com/<your-org>
```

If you used `-IncludeGitHub`, also pass `-GitHubRepo <you>/contoso-logistics` so verification
includes the GitHub Environments and baseline release tag.

You should see **ALL CHECKS PASSED**.

> **Custom project name?** Add `-Project "My Project"` to both scripts.
> **Project already exists on a different process?** Re-run `Provision.ps1` with `-Force` to
> recreate it (⚠️ destructive — deletes the existing project), or pick a new `-Project` name.

### 3.1 Connect the ADO project to your GitHub repo

Do this once, by hand — it can't be scripted with your `az login` token. It's what makes `AB#<id>`
references in commits, branches, and PRs show up in the **Development** section of a work item, and
it's a prerequisite for dispatching the GitHub Copilot coding agent from Azure Boards (§6).

1. In ADO → **Project settings → GitHub connections → Connect your GitHub account**.
2. Authorize Azure Boards for the GitHub account/org that owns your fork.
3. Select your fork (`<you>/contoso-logistics`) → **Save**.
4. Verify: on the repo side, GitHub → **Settings → Integrations → GitHub Apps** lists *Azure Boards*.

Test it: push a commit whose message contains `AB#<id>` for any User Story, then open that story in
ADO — the commit appears under **Development**.

> The release-tracking automation in §8 talks to ADO through the REST API and does **not** depend on
> this connection, but the demo is much more convincing with it in place.

---

## 4. *(Optional)* Azure Pipeline — automated CI

Show an ADO pipeline building & testing the app (mirrors the repo's GitHub Actions CI).

1. Make sure your fork has `azure-pipelines.yml` (it does, at the repo root).
2. Sign in to GitHub CLI: `gh auth login`.
3. Run the optional step, pointing at **your fork**:
   ```powershell
   ./08-Pipeline.ps1 -OrgUrl https://dev.azure.com/<your-org> -GitHubRepo <you>/contoso-logistics
   ```
   (Or include it in the full run: `./Provision.ps1 -OrgUrl ... -IncludePipeline -GitHubRepo <you>/contoso-logistics`.)
4. In ADO → **Pipelines → contoso-logistics-ci → Run pipeline**. The run installs Node, runs
   `npm ci` and `npm test`, and goes green.

> **First run blocked?** New ADO orgs may start with no Microsoft-hosted parallelism. If you see
> a "no hosted parallelism" message, request the free grant (a short form) — only an org admin
> can submit it.

---

## 5. *(Optional)* Microsoft Teams integration

Teams notifications are configured **from Teams**, via the Azure Boards app — not from the ADO
Service hooks page. This step is optional and requires your ADO org and Teams to be in the
**same Microsoft Entra tenant**.

1. In Teams, create a channel for the lab (e.g. a team → **Delivery** channel).
2. **Apps → search "Azure Boards" → Add to a team →** pick your channel → **Set up a bot**.
3. In that channel's conversation:
   ```
   @azure boards signin
   @azure boards link https://dev.azure.com/<your-org>/Contoso%20Logistics
   ```
4. Add a subscription on the **commented** event (deliberately — *work item updated* would spam
   the channel; *commented* is easy to trigger and see):
   ```
   @azure boards subscriptions
   ```
   → **Add subscription** → Event: **Work item commented on** → filter Area path = `Contoso Logistics`.
5. **Test it:** open any User Story in ADO, add a comment → it posts to the Teams channel.

> No Teams in the same tenant? Skip this — use a generic **Web Hook** service hook instead
> (Project Settings → Service hooks → Web Hooks → point at a free https://webhook.site URL).

---

## 6. Evaluate & test each customization

Work through these to see (and prove) what the platform does.

### Inherited process — lightly customized
- **Org Settings → Process → Contoso Agile** — see the inherited Agile process with the
  release-tracking fields and `Ready for Release` User Story state.
- Open **User Story → States** and confirm `Ready for Release` belongs to the
  `Resolved` category, between the `InProgress` and `Completed` categories.
- Add another state if desired: try `In Review` in the `InProgress` category.
- Add a field: **User Story → Fields → New field** → try a picklist called `Risk Level`. (Don't
  reuse `Target Release` — 01-Process.ps1 already creates it as **plain text**, and Azure DevOps
  won't convert a field between picklist and text in place.)
- Add a rule: **User Story → Rules → New rule** → try making a field required when state changes.

### Automation
- **Project Settings → Service hooks** → create a **Web Hooks** subscription to a
  https://webhook.site URL → trigger an event → watch the JSON arrive. (Or use the Teams step above.)

### Team-scoped queries
- **Boards → Queries → Shared Queries → "App Team Stories"** → run it → see only App-area stories.
  Compare with **"DevOps Stories"** to see the platform engineering backlog.
- **"Active Stories"** shows everything currently in progress across all three teams.

### Planning & roadmapping
- **Boards → Backlogs** → switch level to **Epics** → see the Epic → Feature → Story hierarchy
  across Logistics (Order Tracking, Warehouse Automation) and DevOps & Platform Engineering.
- **Boards → Delivery Plans → "Contoso Roadmap"** → see stories across sprints for all three teams,
  with **dependency lines** between sprints (e.g., *Set up build pipeline* → *Add deploy to staging*).
- **Overview → Dashboards → "Contoso Delivery"** → count tiles + pie charts (by State/Area/Sprint).

### Integrations
- **Project Settings → Service hooks** → browse the catalog (Web Hooks, Datadog, Slack, and more).

### Scaling across teams
- **Project Settings → Teams** → see **App Team** / **QA Team** / **DevOps Team**, each with its
  own board over the shared backlog via **area paths** (Boards → choose a team → Boards).

### *(Optional)* CI pipeline
- **Pipelines → contoso-logistics-ci** → open the latest green run.

### *(Optional)* Copilot coding agent
- With your repo linked to the project (§3.1) and the **GitHub Copilot coding agent** enabled, assign a
  User Story to Copilot from Azure Boards → it opens a PR in your repo → CI tests it.

---

## 7. Reset / re-run

Everything is idempotent. To rebuild after changes, just re-run `./Provision.ps1 -OrgUrl ...`.
To start completely fresh, delete the project in the ADO UI (Project Settings → Overview →
Delete) and run the provisioner again.

---

## 8. Release tracking (Azure DevOps + GitHub Actions)

This section documents a second, **optional** scenario layered on top of the base lab above: an
end-to-end release-tracking flow spanning Azure Boards and GitHub Actions. It's structured for a
live demo — read it in order the first time.

### 8.1 Manual setup (do this first — nothing below works without it)

**One-time setup:** if you already provisioned in §3, the only thing this scenario adds is the
GitHub Environments (`dev`/`stage`/`production`) and the **baseline release tag** — so **run these
two only if you haven't already**, i.e. if your §3 run omitted `-IncludeGitHub`:

```powershell
gh auth login
cd provision
./10-GitHubEnvironments.ps1 -GitHubRepo <owner>/contoso-logistics
./11-ReleaseBaseline.ps1    -GitHubRepo <owner>/contoso-logistics
```

`./Verify.ps1 -OrgUrl https://dev.azure.com/<org> -GitHubRepo <owner>/contoso-logistics` tells you
where you stand — it reports `GitHub environment '<name>' not found` for anything still missing.
If you're starting from scratch instead, the full run covers it in one go:

```powershell
az login                    # account that owns the ADO org
gh auth login
cd provision
./Provision.ps1 -OrgUrl https://dev.azure.com/<org> -IncludeGitHub -GitHubRepo <owner>/contoso-logistics
./Verify.ps1   -OrgUrl https://dev.azure.com/<org> -GitHubRepo <owner>/contoso-logistics
```

Then, by hand:

| Step | Where | Why |
|---|---|---|
| Create an ADO PAT with **Work Items (read & write)** | ADO → User settings → Personal access tokens | The release workflows authenticate to ADO with it |
| Add it as repo secret `ADO_PAT` | GitHub → Settings → Secrets and variables → Actions | |
| Add repo variables `ADO_ORG_URL` and `ADO_PROJECT` | Same page, **Variables** tab | Avoids hardcoding org/project in workflow files |
| For each enabled method, set **Allow squash merging → Default commit message** and/or **Allow merge commits → Default commit message** to **"Pull request title and description"** | GitHub → Settings → General → Pull Requests | See below — this carries an `AB#` from PR text into the resulting squash or merge commit. `New-DemoPullRequest.ps1` configures the squash setting used by the demo |
| Confirm you are a required reviewer on the `production` environment | GitHub → Settings → Environments | This is the gate the whole demo pivots on |
| Confirm **Prevent self-review** is **off** | Same page | So you can approve your own deployment while presenting solo |
| Confirm the repo is connected to Azure Boards | ADO → Project settings → GitHub connections | Set up in §3.1. It keeps the native **Development** section on work items populated for traceability during the demo |

> **GitHub plan-tier caveat.** Required reviewers on private repositories need a plan that supports
> environment protection rules. If GitHub rejects that configuration, `10-GitHubEnvironments.ps1`
> creates `production` without an approval gate; confirm the environment before presenting.

> **Why the merge-message settings matter.** `ado-release-sync.yml` derives release membership only
> by reading `AB#<id>` out of commit messages on `main`; it does not query live pull request
> metadata. If a reference lives only in the PR title or description, configure each enabled squash
> or merge commit method to use **Pull request title and description** so the resulting commit
> contains it. Rebase merging creates no result commit, so rebase users must put the `AB#` reference
> in at least one source commit message.

> **`ADO_ORG_URL` — full URL or just the org name?** Either. The reusable workflows trim a trailing
> slash and, if the value has no `http(s)://` scheme, expand it to
> `https://dev.azure.com/<value>`. So `https://dev.azure.com/contoso` and `contoso` are equivalent.
> Use the full URL if your org is on a non-default host.
>
> **`ADO_PROJECT` with spaces?** Fine — set it to the plain, unencoded name (`Contoso Logistics`).
> The workflow scripts URL-encode the project segment, so don't pre-encode it as
> `Contoso%20Logistics`.

**PAT vs. OIDC** — worth stating out loud during the demo:

| Approach | Use when |
|---|---|
| **PAT in `ADO_PAT`** | Demo and lab. One secret, easy to explain. |
| **Entra service principal + GitHub OIDC** | Anything real. No stored secret to rotate across repos, and it reuses the same token pattern the provisioning scripts already use (`az account get-access-token`). |

#### How a release is bounded — read this before running anything

There is **no release branch**. Story pull requests merge into `main` like they would in any normal
repository, and a release is defined as **the span of commits between two git tags**:

```
    0.9.0                                                      1.0.0
      │                                                          │
──────●────●────●────●────●────●────●────●────●────●────●────●────●──────▶  main
      │    └──────────────── release 1.0.0 ────────────────┘     │
  baseline tag                                            tag written by
  (11-ReleaseBaseline.ps1)                                automation on ship
```

`ado-release-sync.yml` resolves the previous release tag reachable from `HEAD` and takes
`<tag>..HEAD`. Three consequences worth saying out loud during the demo:

- **The lower bound maintains itself.** When a release completes, `ado-release-complete.yml` publishes a
  GitHub Release whose tag becomes the *next* release's lower bound. Nobody has to remember to move
  a marker. `11-ReleaseBaseline.ps1` only exists to seed the very first one (`0.9.0`).
- **`version` in `package.json` decides which release is pending.** It's matched against the Release
  work item's `Custom.ReleaseVersion`, and it's the name of the tag/GitHub Release that eventually
  gets published. **Bumping it in a PR is the one human act that opens the next release.**
- **A shipped release is closed for business.** Once `1.0.0` is `Closed`, later sync runs do not
  add new work items to it; the job summary says the release is already closed and prompts you to
  bump `version` to open the next release. That refusal is a feature, not an error.
- **An empty release can't be shipped.** Bumping `version` is itself a merge to `main`, so it queues
  a Deploy run for a release that contains nothing yet. `ado-release-complete.yml` refuses to complete a
  release with no linked work items: no tag, no `Closed` transition, just a warning. Approving that
  run by mistake is therefore harmless — without the guard it would flip the new release to
  `Closed` and write its tag, and subsequent sync runs for that version would refuse to add work.

#### Filling the release — required, and easy to miss

The membership sync only links work items it can find, and it finds them by walking the commits
merged to `main` since the last release tag. **A freshly provisioned lab has none of that**, so a
demo run will start and link nothing.

The intended shape is: walk **one** story end to end by hand (that's §8.4 steps 3–7 — assign it,
implement it, open the PR, watch the check, merge it), then bulk-fill the rest of the release so the
dashboard has something to count:

```powershell
# Preview first — this changes nothing:
./provision/New-DemoPullRequest.ps1 -OrgUrl https://dev.azure.com/<org> -Release '1.0.0' `
    -GitHubRepo <owner>/contoso-logistics -DryRun

# Then, excluding the story you walked live:
./provision/New-DemoPullRequest.ps1 -OrgUrl https://dev.azure.com/<org> -Release '1.0.0' `
    -GitHubRepo <owner>/contoso-logistics -Skip 'Retry failed carrier callbacks' -Merge
```

For each remaining story it cuts a branch off `main`, makes a real change, commits it **with no
`AB#` in the commit message**, opens a pull request that carries
`Ready for Release AB#<id>` in its description, and squash-merges it. The exact
state name tells the native Azure Boards GitHub integration to move the story into
the Resolved category on merge. The script works in a throwaway clone under
`%TEMP%`, so it can't leave your working tree on a stray branch.

> **Why the `AB#` is deliberately kept out of the commit message:** that's the realistic case —
> people forget — and it proves that the configured squash template carries the PR description into
> the resulting commit. `ado-release-sync.yml` never reads the PR directly; after the merge it sees
> the reference only because the squash commit contains that description.

> **Expect a queue of Deploy runs.** `deploy.yml` triggers on every push to `main`, so each merge
> starts one. That is the honest cost of continuous delivery from trunk, and it's worth naming: the
> `production` **environment** is the gate, not the trigger. Cancel the intermediate runs and
> approve production on the **last** one — its commit range is the whole release, because the range
> is recomputed from the tag on every run rather than accumulated. Merging with `-Merge` in one go
> keeps that window short.

<details>
<summary>Offline shortcut: <code>Get-DemoCommits.ps1</code></summary>

If you only need commits on a branch fast — no GitHub, no pull requests, no network round-trips —
`./provision/Get-DemoCommits.ps1 -OrgUrl https://dev.azure.com/<org> -Release '1.0.0'` still
prints ready-to-paste `git commit --allow-empty` commands with
`Ready for Release AB#<id>` in each message. The native integration can still
apply the state transition, but this skips everything interesting about the PR and
its check, so use it as a fallback, not as the demo.

</details>

### 8.2 Reset before each demo

```powershell
./provision/09-Releases.ps1 -OrgUrl https://dev.azure.com/<org> -Reset
```

Plus the GitHub-side cleanup, which `-Reset` cannot do (it only touches Azure DevOps):

```powershell
gh release delete 1.0.0 --cleanup-tag --yes   # remove the release and the tag it wrote

# Re-point the baseline tag at current main — this is what "unships" the release
./provision/11-ReleaseBaseline.ps1 -GitHubRepo <owner>/contoso-logistics -Force

# Close and delete anything left over from the PR walkthrough
gh pr list --search 'head:demo/ab-' --state open --json number --jq '.[].number' |
    ForEach-Object { gh pr close $_ --delete-branch }
git push origin --delete $(git ls-remote --heads origin 'demo/ab-*' |
    ForEach-Object { ($_ -split "`t")[1] -replace '^refs/heads/', '' })
```

> **`main` is never rewritten.** Because the release boundary is a *movable tag* rather than a
> branch diff, moving `0.9.0` forward to today's `main` makes the next run's range empty and the
> demo repeatable — no `git reset --hard`, no force-push, no lost history. The merged walkthrough
> commits simply become part of the pre-release baseline. This is a genuine advantage of the tag
> model over the branch model and is worth pointing out if anyone asks "doesn't merging to `main`
> make this messier?"

If you bumped `version` in `package.json` during the demo, set it back to the release you want to
run next (`1.0.0`) — that is what re-opens it. `09-Releases.ps1 -Reset` has already put the Release
work item back to `New`.

Finish with
`./Verify.ps1 -OrgUrl https://dev.azure.com/<org> -GitHubRepo <owner>/contoso-logistics` to confirm
a clean baseline.

Have these tabs open before you start: the ADO **board**, the ADO **Contoso Delivery** dashboard,
**GitHub Actions**, and **GitHub Environments**.

### 8.3 The mechanics (brief reference)

- **`Release`** is a brand-new custom work item type — states `New → Active → Closed` —
  deliberately kept **off every backlog level**. A work item has only one parent,
  and stories already parent to Features, so `Release` is linked via `System.LinkTypes.Related`
  only, never a hierarchy/child link.
- **`Target Release`** (`Custom.TargetRelease`, plain text) is *intent* — set by a product owner.
  **`Shipped Release`** (`Custom.ShippedRelease`, plain text) is *actual* — written only by
  automation. Both are plain text, which means nothing validates a story's Target Release against
  a real Release work item; that's deliberate (a picklist would make every new release a process
  migration, since ADO can't convert a field between picklist and text). They are allowed to
  disagree; when they do, that's drift (see the optional demo below).
- **Releases are bounded by git tags, not branches.** A release's contents are
  `<previous release tag>..HEAD` on `main`, recomputed on every push — so the pending release
  contents are always live, and there is no branch to cut or keep in sync. The tag that closes one
  release is the tag that opens the next, and `version` in `package.json` names it.
- Two events drive everything:

  | Event | Meaning | Automation |
  |---|---|---|
  | Merge into `main` | Membership decided | `ado-release-sync.yml` links story ↔ Release, stamps `Shipped Release` |
  | Production deploy succeeds | Definition of done met | `ado-release-complete.yml` transitions stories, publishes release notes **and writes the tag that bounds the next release** |

- This whole scenario adds **one `Ready for Release` state and two release fields to User Story**,
  plus a custom **Release** work item type with three states and four fields.

### 8.4 Happy-path walkthrough (~20–25 min)

Steps 2–7 are the part worth slowing down for: **one real work item, taken all the way from the
board to production.** Nothing is faked, and every link the automation later relies on is created
in front of the audience.

1. **(2 min)** Show the clean baseline: Release work items exist in ADO with nothing linked, and
   the `Contoso Delivery` dashboard's release tiles read zero. Show `version` in `package.json`
   (`1.0.0`) and `git tag --list` (`0.9.0`) side by side — **those two values are the release**:
   everything after `0.9.0`, shipping as `1.0.0`.

2. **(1 min)** *As the product owner.* Open the story **Retry failed carrier callbacks** on the
   board and set its **Target Release** to `1.0.0`.

   > **What to say:** this field is *intent*. Nobody has written any code. The only thing that has
   > happened is a human saying where they'd like this to land — and that's the only thing a human
   > will be asked to say about this release for the rest of the demo.

3. **(4 min)** *As the developer.* Branch off `main` and implement the story for real — it's a stub
   waiting in `src/services/carriers.js`:

   ```powershell
   git switch -c feature/carrier-retry origin/main
   ```

   `retryFailedCallbacks()` currently throws `Not implemented`. Implement it (a good moment to hand
   the keyboard to Copilot — the TODO comment names the story) and add a test in
   `test/`. Run `npm test` to prove it's green.

4. **(2 min)** Commit **without** an `AB#` reference, and open the pull request against `main`:

   ```powershell
   git commit -am "feat: retry failed carrier callbacks with exponential backoff"
   git push -u origin feature/carrier-retry
   gh pr create --base main --title "Retry failed carrier callbacks" --body "Ready for Release AB#<id>"
   ```

   > **What to say:** this is an ordinary pull request into an ordinary trunk. There is no release
   > branch to know about, no "which release am I targeting?" question at PR time. Where it lands
   > is decided by *when* it merges, not by what the author picked.

   > **What to say:** the commit message has no work item reference, because in real life it often
   > won't. The reference is on the pull request, where the author was already typing,
   > and the exact state name asks Azure Boards to transition it when the PR merges.

   Optionally, do it the other way round to make the point harder: open the PR with **no `AB#`
   anywhere**, let the check fail, then edit the PR description to add
   `Ready for Release AB#<id>` and watch the check pass. Linking the PR manually from the work
   item's **Development** section is useful for traceability, but the current check does not query
   Azure Boards links.

5. **(2 min)** Open the **PR Work Item Check** run. Its summary is a table of every place a
   reference could have come from — title, body, commits, and comments. Point out which rows are
   populated.

6. **(1 min)** Switch to ADO and open the story. The **Development** section now shows the pull
   request. That link was created by the Azure Boards GitHub app from the `AB#` in the PR
   description — nobody related anything by hand.

7. **(1 min)** Squash-merge the PR. This lands on `main`, moves the story from
   `Active` to `Ready for Release` through the native integration, and immediately
   starts a Deploy run.

8. **(2 min)** Bulk-fill the rest of the release:

   ```powershell
   ./provision/New-DemoPullRequest.ps1 -OrgUrl https://dev.azure.com/<org> -Release '1.0.0' `
       -GitHubRepo <owner>/contoso-logistics -Skip 'Retry failed carrier callbacks' -Merge
   ```

9. **(2 min)** In GitHub Actions, cancel any queued Deploy runs and open the **latest** one. Read
    the `sync-release-membership` job summary: the resolved commit range (`0.9.0..HEAD`), the number
    of `AB#` references found, newly linked and already-linked items, unresolved references, and
    any drift.

    > **What to say:** the story you implemented is in that list, and its commit never mentioned a
    > work item before the merge. The configured squash template copied the PR description into the
    > squash commit, and release sync found the reference in that commit history. Note the range at
    > the top of the summary — every run recomputes it from the tag, so cancelling the earlier runs
    > cost nothing. The last run always sees the whole release.

10. **(1 min)** Switch to ADO: merged stories are `Ready for Release`, the `1.0.0`
    Release work item shows `Related` links to them, and its state has moved
    `New → Active`. Azure Boards owns the story state transition; release sync owns
    the Release links and `Shipped Release` stamps.
11. **(3 min)** Watch `deploy-dev` and `deploy-stage` run to completion; `deploy-prod` sits waiting
    for approval — point out this is the `environment: production` gate, not a workflow input or a
    branch condition.
12. **(1 min)** Approve the deployment (Actions → the running workflow → **Review deployments**).
13. **(3 min)** Watch `deploy-prod` finish, then the `complete-release` job run: stories flip to
    `Closed`, the Release work item flips to `Closed` with `Deployed On`/`Deployed By`/
    `Release Notes URL` populated, and a GitHub Release appears with auto-generated notes.

    > **What to say:** run `git fetch --tags && git tag --list` now — there's a `1.0.0` tag that
    > nobody created by hand. **That tag is the lower bound of the next release.** The boundary
    > maintains itself; the only thing a human does to start release two is bump `version` in
    > `package.json`.

14. **(1 min)** Return to the ADO dashboard: **Shipped but Not Closed** now reads zero.

    > **What to say:** this tile is the scoreboard. It reading zero without anyone opening a board
    > and clicking "Close" on a single item is the entire point of this scenario. The only board
    > interaction in the last twenty minutes was step 2 — a product owner stating intent.

### 8.5 *(Optional)* Demonstrating the drift problem (~15–20 min — roughly doubles the demo)

Do this when the audience needs to *feel* the reconciliation problem before seeing it solved. Skip
it for a short demo — go straight from step 14 above to Q&A.

**Act 1 — stage the pain by hand.** Start from a clean baseline (`09-Releases.ps1 -Reset`).
Explain that in the manual version of this process, release membership is *declared by a human*
rather than *derived from the merge* — then create each failure mode live in the ADO UI:

| Do this in the ADO UI | What it represents | What breaks |
|---|---|---|
| Set a story's `Shipped Release` to a release different from its `Target Release` | Scope creep — shipped somewhere it wasn't planned | Appears in **Release Drift - 1.0.0** |
| Set `Shipped Release` on a story that's still active/unresolved | Code is live but the board disagrees | Appears in **Shipped but Not Closed** |
| Remove a story's `Related` link to its Release | Someone forgot the manual relate step | Silently missing from release contents |
| Attach a story to a Release with a **Child** link instead of `Related` | The wrong-link-type trap | Competes with the story's existing Feature parent |
| Push a commit with no `AB#` reference, from a branch with no pull request | Untracked work | It bypasses the PR check and release sync cannot link it; the current summary does not identify unreferenced commits |
| Ship work, then keep merging without bumping `version` | The "which release is this in?" gap | Sync reports that the selected Release is already closed and links nothing until someone bumps `version` |

Refresh the dashboard and let the tiles go red.

**The line to land:** every one of these has to be found and fixed by a person, before every
release, by reading merge history and cross-checking a board. The cause isn't a missing feature —
it's that **people are being asked to state the same fact twice, and the second statement has no
immediate consequence**, so it drifts.

**Act 2 — show it relieved.**

```powershell
./provision/09-Releases.ps1        -OrgUrl <org> -Reset
./provision/11-ReleaseBaseline.ps1 -GitHubRepo <owner>/contoso-logistics -Force
```

Then run the happy path (8.4) again. Call out, at each step, which manual failure mode just became
structurally impossible:

| Was | Now |
|---|---|
| Someone relates stories by hand and forgets | Derived from the merge, on every push |
| Someone marks stories done after deploy | Transitioned automatically, post-approval |
| Someone assembles release contents in a doc | The GitHub Release notes, generated |
| Pull requests with no `AB#` reference at all | Flagged by the required PR check before merge |
| Someone decides, later, what "was in" a release | The tag boundary decided it at merge time |

Close on the dashboard reading zero.

### 8.6 The PR work-item check, and how it scales

`.github/workflows/pr-workitem-check.yml` requires every pull request to carry an AB# reference.
Any **one** of these can make the status check pass when the workflow runs:

| # | Source | Notes |
|---|---|---|
| 1 | `AB#<id>` in the **PR title** | Preferred for configured squash or merge commits; rebase still requires a commit-message reference |
| 2 | `AB#<id>` in the **PR description** | Supports the Azure Boards state transition; configure squash/merge messages as described in §8.1 |
| 3 | `AB#<id>` in any **commit message** | Directly visible to release sync and required when using rebase merging |
| 4 | `AB#<id>` in a **PR comment** | Check-only: comments are not copied into commit history, and adding one does not trigger this workflow by itself |

The job summary is a table of all four sources with what each one found, so a failed check tells the
author what was actually looked at rather than just "no reference found".

Passing this check is not by itself proof that release sync can derive membership:
`ado-release-sync.yml` reads commit messages only. Use PR title/body references with the configured
squash or merge commit templates, use a commit-message reference for rebase merging, and do not rely
on a comment-only reference for release membership.

An operational note worth saying out loud:

- **`vars.WORK_ITEM_CHECK_ENFORCEMENT = warn`** turns the check into a reporting-only soft launch:
  same summary, never fails. Useful when introducing this to a team that has years of history
  without references.

To make that a guardrail across many repositories, pair it with an **organisation-level repository
ruleset** that requires the check to pass before merging. Rulesets enforce the *result* of a check —
each repository still needs its own (small, reusable-workflow-backed) copy of the workflow file to
produce it. GitHub's older "required workflows" feature, which could inject runs with no per-repo
YAML at all, has been retired; rulesets plus a thin per-repo workflow are the current pattern.

---

## 9. Further learning — official Microsoft documentation

- **Customize an inherited process** — https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/manage-process
- **Configure & customize Azure Boards** — https://learn.microsoft.com/en-us/azure/devops/boards/configure-customize
- **Rules reference (validation rules)** — https://learn.microsoft.com/en-us/azure/devops/organizations/settings/work/rule-reference
- **Areas & iteration paths** — https://learn.microsoft.com/en-us/azure/devops/organizations/settings/about-areas-iterations
- **Delivery Plans** — https://learn.microsoft.com/en-us/azure/devops/boards/plans/review-team-plans
- **Dashboards & widget catalog** — https://learn.microsoft.com/en-us/azure/devops/report/dashboards/widget-catalog
- **Queries / WIQL syntax** — https://learn.microsoft.com/en-us/azure/devops/boards/queries/wiql-syntax
- **Service hooks overview** — https://learn.microsoft.com/en-us/azure/devops/service-hooks/overview
- **Azure Boards app for Microsoft Teams** — https://learn.microsoft.com/en-us/azure/devops/boards/integrations/boards-teams
- **Azure Pipelines** — https://learn.microsoft.com/en-us/azure/devops/pipelines/
- **Plan your org & team structure (scaling)** — https://learn.microsoft.com/en-us/azure/devops/user-guide/plan-your-azure-devops-org-structure
- **About projects** — https://learn.microsoft.com/en-us/azure/devops/organizations/projects/about-projects
- **GitHub Copilot coding agent** — https://docs.github.com/copilot
- **GitHub Environments (deployment protection rules)** — https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment
- **Reusable workflows** — https://docs.github.com/en/actions/using-workflows/reusing-workflows
- **Repository rulesets** — https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
