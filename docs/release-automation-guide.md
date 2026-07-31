# Release Automation Guide (GitHub Actions + Azure Boards)

## 1. Scope

Use this to implement release membership + release completion automation in your own GitHub repo and Azure DevOps project.

- Azure DevOps is used for Boards/work items only.
- GitHub Actions runs the automation.
- Release boundaries are semver tags.

## 2. Required workflow assets (relative paths)

Copy these workflow files into your repository at the same paths:

- [`.github/workflows/ado-release-sync.yml`](../.github/workflows/ado-release-sync.yml)
- [`.github/workflows/ado-release-complete.yml`](../.github/workflows/ado-release-complete.yml)
- [`.github/workflows/pr-workitem-check.yml`](../.github/workflows/pr-workitem-check.yml)

Do **not** copy [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) verbatim unless your deployment model already matches it. Treat it as a reference implementation.

## 3. Integrate with your existing deployment workflow

Add the minimum jobs/snippets below into your existing deployment workflow (the one that deploys `main` across environments).

### 3.1 Resolve release metadata once

Place this near the top of your jobs graph so later jobs can reuse outputs:

```yaml
# Resolves the release version and commit SHA once so downstream jobs can reuse them.
jobs:
  resolve-release:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.resolve.outputs.version }}
      sha: ${{ steps.resolve.outputs.sha }}
    steps:
      - uses: actions/checkout@v4
      - id: resolve
        run: |
          version="$(jq -r .version package.json)"
          echo "version=$version" >> "$GITHUB_OUTPUT"
          echo "sha=${{ github.sha }}" >> "$GITHUB_OUTPUT"
```

### 3.2 Run release membership sync after merge to main

Add this job after `resolve-release`, before/alongside environment deploy jobs:

```yaml
# Syncs commit-derived work item membership into the active Azure Boards release.
  sync-release-membership:
    needs: resolve-release
    permissions:
      contents: read
    uses: ./.github/workflows/ado-release-sync.yml
    with:
      ado-org-url: ${{ vars.ADO_ORG_URL }}
      ado-project: ${{ vars.ADO_PROJECT }}
      release-version: ${{ needs.resolve-release.outputs.version }}
    secrets: inherit
```

### 3.3 Run release completion only after production succeeds

Ensure your production deploy job is environment-gated (`environment: production`), then add:

```yaml
# Completes Azure Boards release tracking only after the production deployment succeeds.
  complete-release:
    needs: [resolve-release, deploy-prod]
    permissions:
      contents: write
    uses: ./.github/workflows/ado-release-complete.yml
    with:
      ado-org-url: ${{ vars.ADO_ORG_URL }}
      ado-project: ${{ vars.ADO_PROJECT }}
      version: ${{ needs.resolve-release.outputs.version }}
      commit-sha: ${{ needs.resolve-release.outputs.sha }}
    secrets: inherit
```

`deploy-prod` is your existing production deployment job name. If yours differs, update the `needs` dependency accordingly.

### 3.4 Placement rules that must stay true

- Trigger your deployment workflow from pushes/merges to `main`.
- Keep release boundaries tag-based (semver tags), not branch-based.
- Keep production approval enforced by the GitHub `production` Environment.
- Keep release automation non-blocking by preserving step-level `continue-on-error` in reusable workflows.

## 4. Prerequisites

1. Azure Boards is already connected to the GitHub repository.
2. `main` is your deployment branch.
3. `package.json` contains the release version used to select the active Release work item.
4. A baseline semver tag exists before first run (example: `0.9.0`).

## 5. Azure DevOps minimum schema setup

Create these process customizations in the ADO process used by your project.

### 5.1 User Story fields (text)

- `Custom.TargetRelease` (Target Release)
- `Custom.ShippedRelease` (Shipped Release)

### 5.2 User Story state

- Add `Ready for Release` to the existing `Resolved` state category.
- Keep Azure DevOps's category order: `InProgress` → `Resolved` → `Completed`.
- In GitHub pull request descriptions, use `Ready for Release AB#<id>` so the
  native Azure Boards integration applies the state when the PR merges. Separately, use the
  merge-message settings in §6.4 so the reference also reaches release commit history.

### 5.3 Custom work item type: `Release`

States:

- `New`
- `Active`
- `Closed`

Fields:

- `Custom.ReleaseVersion` (text)
- `Custom.DeployedOn` (dateTime)
- `Custom.DeployedBy` (text)
- `Custom.ReleaseNotesUrl` (text)

### 5.4 Link behavior

- Keep release-to-story links as `System.LinkTypes.Related`.
- Do not use hierarchy parent/child links for Release membership.

### 5.5 Seed release work items

Create one `Release` work item per version you plan to ship (example `1.0.0`, `1.1.0`).

- `System.Title` = version string (recommended)
- `Custom.ReleaseVersion` = same version string
- Initial state = `New`

## 6. GitHub setup

### 6.1 Environments

Create environments:

- `dev`
- `stage`
- `production`

Set required reviewer(s) on `production`.

Required reviewers on private repositories require a GitHub plan that supports environment
protection rules. If unavailable, the environment can still exist but production will not have the
approval gate described by this guide.

### 6.2 Repository secret

Create Actions secret:

- `ADO_PAT` = Azure DevOps PAT with **Work Items (Read & Write)** scope

### 6.3 Repository variables

Create Actions variables:

- `ADO_ORG_URL` (full URL like `https://dev.azure.com/contoso` or org slug like `contoso`)
- `ADO_PROJECT` (plain project name, not URL-encoded)

### 6.4 Pull request merge-message settings

For each enabled merge method that creates a result commit, set the default commit message to
include the pull request title and description:

- **Allow squash merging -> Default commit message -> Pull request title and description**
- **Allow merge commits -> Default commit message -> Pull request title and description**

`ado-release-sync.yml` reads `AB#` references from commit history, not live pull request metadata.
These settings copy PR title/body references into the resulting squash or merge commit. If you
allow rebase merging, put the `AB#` reference in at least one source commit message because a
rebase creates no result commit that can carry the PR title or description.

## 7. Post-setup validation (quick)

1. Open a PR with `AB#<id>` in title.
2. Confirm `PR Work Item Check` passes.
3. Merge to `main`.
4. Confirm `Deploy` runs and `ADO Release Sync` links/stamps work items.
5. Approve `production` environment.
6. Confirm `ADO Release Complete` closes linked stories, closes the Release item, and publishes a GitHub Release tag.

## 8. Optional: scale pattern (org-wide)

Use this only if you are rolling out to many repositories.

### 8.1 Template repository

Create a central workflow-template repository (example `org/release-automation-workflows`) containing:

- `.github/workflows/ado-release-sync.yml`
- `.github/workflows/ado-release-complete.yml`
- optional shared PR check workflow

Then reference reusable workflows from app repos:

```yaml
# Calls a centrally versioned release-membership workflow from an application repository.
jobs:
  sync-release-membership:
    uses: org/release-automation-workflows/.github/workflows/ado-release-sync.yml@v1
    with:
      ado-org-url: ${{ vars.ADO_ORG_URL }}
      ado-project: ${{ vars.ADO_PROJECT }}
      release-version: ${{ needs.resolve-release.outputs.version }}
    secrets: inherit
```

### 8.2 Secrets and variables layering

- **Org-level secret**: `ADO_PAT` (shared where policy allows)
- **Org-level variable**: `ADO_ORG_URL`
- **Repo-level variable**: `ADO_PROJECT` (usually project-specific)
- **Repo-level variable (optional)**: `WORK_ITEM_CHECK_ENFORCEMENT`

### 8.3 Rollout sequence

1. Publish template workflows and tag a version (for example `v1`).
2. Configure org secret/variable defaults.
3. Update each repository deployment workflow to call template workflows.
4. Set repo-specific `ADO_PROJECT`.
5. Enable required PR check in branch protection/rulesets.
6. Validate one pilot repo, then batch rollout.

### 8.4 Reusable workflow vs composite action

Prefer **reusable workflows** for this scenario.

- Reusable workflows can model job-level dependencies (`needs`) across deploy and post-deploy phases.
- Reusable workflows fit environment-gated production jobs and cross-job outputs cleanly.
- Composite actions run as steps inside a single job, so they are a poor fit for gating logic that depends on another job (`deploy-prod`) completing.

Use composite actions only for small, shared step bundles, not for release lifecycle orchestration.
