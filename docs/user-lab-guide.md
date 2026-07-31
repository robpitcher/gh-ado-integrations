# Contoso Logistics - Administrator Lab Guide

This guide is for DevOps engineers and Azure DevOps administrators who want to deploy the Contoso
Logistics lab in their own environment. It focuses on environment preparation, provisioning,
configuration, validation, operation, and cleanup.

> [!IMPORTANT]
> This repository is a proof of concept and learning lab. Review and adapt its identity,
> permissions, secrets, deployment, resilience, and operational controls before applying any
> pattern to a production system.

## 1. What the lab creates

The lab combines Azure Boards, optional Azure Pipelines integration, and GitHub Actions release
tracking.

The base provisioner creates:

- An inherited Azure DevOps process named **Contoso Agile**
- A **Contoso Logistics** project, or a project name you provide
- **App Team**, **QA Team**, and **DevOps Team**
- Area paths and three sprint iterations
- 3 Epics, 9 Features, and 34 User Stories with dependencies
- A custom **Ready for Release** User Story state
- **Target Release** and **Shipped Release** User Story fields
- A custom **Release** work item type and seeded `1.0.0`, `1.1.0`, and `1.2.0` releases
- Shared queries, the **Contoso Delivery** dashboard, and the **Contoso Roadmap** Delivery Plan

Optional components include:

- An Azure Pipeline that installs dependencies and runs the test suite
- Microsoft Teams notifications or a generic service hook
- GitHub Copilot coding agent integration through Azure Boards
- GitHub Environments and GitHub Actions release tracking

### Release architecture

The release-tracking scenario uses Azure Boards for work items and GitHub Actions for deployment
and release automation.

- Pull requests merge into `main`; there is no release branch.
- A release contains the commits in `<previous semver tag>..HEAD`.
- `package.json` `version` selects the pending Azure Boards Release work item.
- Merge to `main` decides release membership.
- Successful production deployment completes the release.
- The published GitHub Release tag becomes the lower boundary for the next release.

## 2. Prerequisites and permissions

| Requirement | Purpose |
|---|---|
| **PowerShell 7+** (`pwsh`) | Runs the provisioning scripts |
| **Azure CLI** (`az`) | Obtains an Entra token for Azure DevOps |
| **Azure DevOps organization** | Hosts the process, project, Boards data, dashboards, and plans |
| **GitHub account and fork** | Required for GitHub integrations and release automation |
| **GitHub CLI** (`gh`) | Creates GitHub resources and the optional Azure Pipeline connection |
| **Node.js 20+** | Runs the sample application and its tests |

The Azure identity used with `az login` must be able to:

- Create and customize inherited processes
- Create or delete projects
- Configure teams, area paths, iterations, queries, dashboards, and Delivery Plans
- Create and update work items
- Configure GitHub connections for the project

The GitHub identity used with `gh auth login` must have administrative access to the target
repository when provisioning environments or repository settings.

The scripts obtain an Azure DevOps token from the current Azure CLI login. They do not require or
store a PAT for provisioning. The GitHub Actions release workflows require a separate Azure DevOps
PAT, described in [section 9](#9-configure-release-automation).

> [!NOTE]
> The Azure DevOps organization and Microsoft Teams must be in the same Microsoft Entra tenant to
> use the Azure Boards Teams app.

## 3. Fork, clone, and authenticate

Fork this repository into the GitHub account or organization that will own the lab, then clone the
fork:

```powershell
git clone https://github.com/<owner>/contoso-logistics.git
cd contoso-logistics
```

Authenticate to Azure and GitHub:

```powershell
az login
gh auth login
```

Confirm the selected identities before provisioning:

```powershell
az account show
gh auth status
```

Run all provisioning commands from a PowerShell 7 session.

## 4. Choose the lab components

| Scenario | Provisioning options |
|---|---|
| Azure Boards lab only | No optional switches |
| Azure Boards plus Azure Pipeline | `-IncludePipeline -GitHubRepo <owner>/contoso-logistics` |
| Azure Boards plus GitHub release tracking | `-IncludeGitHub -GitHubRepo <owner>/contoso-logistics` |
| Complete lab | `-IncludePipeline -IncludeGitHub -GitHubRepo <owner>/contoso-logistics` |

`-IncludePipeline` creates an Azure Pipeline backed by the GitHub repository.

`-IncludeGitHub` creates the `dev`, `stage`, and `production` GitHub Environments and seeds the
baseline `0.9.0` tag used to bound the first release.

## 5. Provision the Azure DevOps lab

From the repository root:

```powershell
cd provision
./Provision.ps1 -OrgName <your-org> -IncludePipeline -IncludeGitHub `
    -GitHubRepo <owner>/contoso-logistics
```

`-OrgName` accepts either an organization slug such as `contoso` or a full URL such as
`https://dev.azure.com/contoso`. `-Org` and `-OrgUrl` are aliases.

To use a different Azure DevOps project name:

```powershell
./Provision.ps1 -OrgName <your-org> -Project "My Project"
```

### Provisioning parameters

| Parameter | Default | Purpose |
|---|---|---|
| `-OrgName` | Required | Azure DevOps organization slug or URL |
| `-Project` | `Contoso Logistics` | Project to create or update |
| `-Force` | Off | Deletes and recreates a project that uses a different process |
| `-IncludePipeline` | Off | Creates the optional Azure Pipeline |
| `-IncludeGitHub` | Off | Creates GitHub Environments and the baseline tag |
| `-GitHubRepo` | None | Required with either optional integration switch |

> [!CAUTION]
> `-Force` is destructive when the named project already exists on a different process. Use a new
> project name unless deleting and recreating the existing project is intentional.

### Provisioning sequence

`Provision.ps1` runs these idempotent steps:

| Script | Result |
|---|---|
| [`01-Process.ps1`](../provision/01-Process.ps1) | Inherited process, release fields, state, and Release work item type |
| [`02-Project.ps1`](../provision/02-Project.ps1) | Azure DevOps project |
| [`03-Structure.ps1`](../provision/03-Structure.ps1) | Teams, area paths, and iterations |
| [`04-WorkItems.ps1`](../provision/04-WorkItems.ps1) | Seeded portfolio and team work items |
| [`09-Releases.ps1`](../provision/09-Releases.ps1) | Seeded Release work items |
| [`05-Views.ps1`](../provision/05-Views.ps1) | Queries and dashboard |
| [`06-Layout.ps1`](../provision/06-Layout.ps1) | User Story form controls |
| [`07-Plans.ps1`](../provision/07-Plans.ps1) | Delivery Plan |
| [`08-Pipeline.ps1`](../provision/08-Pipeline.ps1) | Optional Azure Pipeline |
| [`10-GitHubEnvironments.ps1`](../provision/10-GitHubEnvironments.ps1) | Optional GitHub Environments |
| [`11-ReleaseBaseline.ps1`](../provision/11-ReleaseBaseline.ps1) | Optional initial release boundary tag |

Each numbered script can also run independently. Environment variables `ADO_ORG_NAME` (or the
legacy `ADO_ORG_URL`) and `ADO_PROJECT` can supply defaults to individual scripts.

### Verify provisioning

Run:

```powershell
./Verify.ps1 -OrgName <your-org> -GitHubRepo <owner>/contoso-logistics
```

Omit `-GitHubRepo` if GitHub Environments were not included. A complete base setup reports
`ALL CHECKS PASSED`.

## 6. Connect Azure Boards to GitHub

This connection cannot be created by the provisioner using the Azure CLI token. Configure it once
in the Azure DevOps UI:

1. Open **Project settings > GitHub connections**.
2. Select **Connect your GitHub account**.
3. Authorize the Azure Boards GitHub App for the account or organization that owns the fork.
4. Select `<owner>/contoso-logistics` and save.
5. In GitHub, open **Settings > Integrations > GitHub Apps** and confirm **Azure Boards** is
   installed for the repository.

This connection populates the **Development** section of Azure Boards work items when commits,
branches, or pull requests contain `AB#<id>`. It is also required when dispatching the GitHub
Copilot coding agent from Azure Boards.

The GitHub Actions release workflows call the Azure DevOps REST API directly and do not depend on
this connection for release membership. Keep the connection enabled for native traceability and
work item state transitions.

## 7. Configure optional integrations

### 7.1 Azure Pipeline

The repository includes [`azure-pipelines.yml`](../azure-pipelines.yml). If the pipeline was not
created during the main provisioning run, run:

```powershell
./08-Pipeline.ps1 -OrgName <your-org> -Project "Contoso Logistics" `
    -GitHubRepo <owner>/contoso-logistics
```

Then open **Pipelines > contoso-logistics-ci** in Azure DevOps and run the pipeline. It runs
`npm ci` and `npm test`.

New Azure DevOps organizations may not have Microsoft-hosted parallelism. An organization
administrator must request the free parallelism grant or configure a self-hosted agent before the
pipeline can run.

### 7.2 Microsoft Teams or a generic service hook

To configure Teams:

1. Add the **Azure Boards** app to the target Teams channel.
2. In the channel, run `@azure boards signin`.
3. Run `@azure boards link https://dev.azure.com/<your-org>/Contoso%20Logistics`.
4. Open `@azure boards subscriptions`.
5. Add a subscription such as **Work item commented on**, filtered to the project area path.
6. Add a comment to a User Story and confirm the notification reaches the channel.

If Teams is unavailable or in a different Entra tenant, configure a generic Web Hook under
**Project settings > Service hooks** and send a test event to an HTTPS endpoint you control.

### 7.3 GitHub Copilot coding agent

After the Azure Boards GitHub connection is active:

1. Confirm the GitHub Copilot coding agent is enabled for the repository and users.
2. Confirm repository policies allow the agent to create branches and pull requests.
3. Assign a suitable Azure Boards User Story to Copilot.
4. Confirm the generated pull request links back to the work item and runs the repository checks.

Review GitHub's current Copilot licensing, repository access, and policy requirements before using
this integration outside the lab.

## 8. Validate the Azure DevOps configuration

Use this checklist after provisioning:

- **Organization settings > Process > Contoso Agile**
  - User Story contains **Ready for Release** in the Resolved category.
  - User Story contains `Custom.TargetRelease` and `Custom.ShippedRelease`.
  - The custom **Release** work item type contains `New`, `Active`, and `Closed`.
- **Project settings > Teams**
  - App Team, QA Team, and DevOps Team exist with the expected area paths.
- **Boards > Backlogs**
  - Epic, Feature, and User Story hierarchy is populated.
- **Boards > Queries > Shared Queries**
  - Team and release queries return project-scoped results.
- **Boards > Delivery Plans > Contoso Roadmap**
  - All three teams and cross-sprint dependencies are visible.
- **Overview > Dashboards > Contoso Delivery**
  - Count and chart widgets load without configuration errors.
- **Boards > Work Items**
  - Release work items `1.0.0`, `1.1.0`, and `1.2.0` exist.
- **Pipelines**
  - The optional pipeline completes successfully when enabled.

## 9. Configure release automation

The repository contains the following authoritative workflow files:

- [`deploy.yml`](../.github/workflows/deploy.yml) - reference multi-environment deployment flow
- [`ado-release-sync.yml`](../.github/workflows/ado-release-sync.yml) - release membership sync
- [`ado-release-complete.yml`](../.github/workflows/ado-release-complete.yml) - post-production completion
- [`pr-workitem-check.yml`](../.github/workflows/pr-workitem-check.yml) - pull request work item guard

For a focused integration reference, also see
[`release-automation-guide.md`](release-automation-guide.md).

### 9.1 Confirm the Azure DevOps schema

The provisioner creates the required schema:

| Type | Name | Reference name or behavior |
|---|---|---|
| User Story field | Target Release | `Custom.TargetRelease`, plain text |
| User Story field | Shipped Release | `Custom.ShippedRelease`, plain text |
| User Story state | Ready for Release | Resolved state category |
| Work item type | Release | Kept off backlog levels |
| Release field | Release Version | `Custom.ReleaseVersion` |
| Release field | Deployed On | `Custom.DeployedOn` |
| Release field | Deployed By | `Custom.DeployedBy` |
| Release field | Release Notes URL | `Custom.ReleaseNotesUrl` |

Release membership must use `System.LinkTypes.Related`. Do not use parent/child links because a
User Story already uses its hierarchy parent for its Feature.

The release selector fields are intentionally plain text. Adding a version does not require an
Azure DevOps process migration, but Azure DevOps does not validate that a Target Release value
matches an existing Release work item.

### 9.2 Create GitHub Environments and the baseline tag

If the initial provisioning run did not use `-IncludeGitHub`, run:

```powershell
./10-GitHubEnvironments.ps1 -GitHubRepo <owner>/contoso-logistics
./11-ReleaseBaseline.ps1 -GitHubRepo <owner>/contoso-logistics
```

Confirm GitHub contains:

- `dev`, `stage`, and `production` Environments
- A required reviewer on `production`
- A `main` deployment branch policy on `production`
- A baseline `0.9.0` tag

The provisioning script leaves **Prevent self-review** off so the authenticated administrator can
approve their own lab deployment. Enable it and assign a separate reviewer when multiple
administrators are available.

Required reviewers on private repositories require a GitHub plan that supports deployment
protection rules. If the plan does not support them, the script creates the production Environment
without an approval gate and reports the limitation.

### 9.3 Configure Azure DevOps credentials for GitHub Actions

Create an Azure DevOps PAT with **Work Items (Read & write)** scope. Store it as the repository
Actions secret:

| Type | Name | Value |
|---|---|---|
| Secret | `ADO_PAT` | Azure DevOps PAT |
| Variable | `ADO_ORG_URL` | Organization URL or slug |
| Variable | `ADO_PROJECT` | Plain, unencoded project name |

Configure these under **GitHub > Settings > Secrets and variables > Actions**.

`ADO_ORG_URL` can be `https://dev.azure.com/contoso` or `contoso`. If the project name contains
spaces, use the plain value such as `Contoso Logistics`; the workflows URL-encode it.

For a production implementation, prefer an Entra service principal with GitHub OIDC over a
long-lived PAT. The provided workflows use `ADO_PAT` to keep the lab setup simple.

### 9.4 Configure pull request merge messages

Release sync reads `AB#<id>` references from commit history, not live pull request metadata.

For each enabled method, configure:

- **Allow squash merging > Default commit message > Pull request title and description**
- **Allow merge commits > Default commit message > Pull request title and description**

For rebase merging, include the `AB#` reference in at least one source commit message because
rebase creates no result commit that can carry the pull request title or description.

Prefer putting `AB#<id>` in the pull request title. A description containing
`Ready for Release AB#<id>` also allows the Azure Boards GitHub integration to apply the state
transition after merge, provided the repository merge-message configuration carries it into commit
history.

The PR Work Item Check inspects the pull request title, description, commits, and comments. A
comment-only reference can pass the check, but it does not reach commit history and therefore
cannot establish release membership. Adding a comment alone also does not trigger a new check run.

Set repository variable `WORK_ITEM_CHECK_ENFORCEMENT` to `warn` for a non-blocking rollout. For
enforcement, require the check through a repository or organization ruleset.

### 9.5 Integrate with the deployment workflow

[`deploy.yml`](../.github/workflows/deploy.yml) is a working reference for this lab. When adapting
the automation to another repository, preserve these job relationships:

1. Resolve the release version from `package.json` and the current commit SHA.
2. Run the reusable membership workflow after a push or merge to `main`.
3. Deploy through the required environments.
4. Gate the production deployment with `environment: production`.
5. Run the reusable completion workflow only after production succeeds.

Do not copy the reference deployment workflow unchanged unless its deployment model matches the
target application. Instead, call the two reusable workflows from the application's existing
deployment workflow as documented in
[`release-automation-guide.md`](release-automation-guide.md).

Keep work-tracking failures from blocking deployment by retaining step-level `continue-on-error`
inside the reusable workflows. GitHub does not allow `continue-on-error` on a job that calls a
reusable workflow with `uses:`.

### 9.6 Understand the release lifecycle

For pending version `1.0.0` and baseline tag `0.9.0`, membership is derived from:

```text
0.9.0..HEAD
```

On each push to `main`, release sync:

- Resolves the previous reachable semver tag
- Extracts `AB#` references from commit messages in the range
- Finds the Release work item selected by `package.json` `version`
- Creates Related links between the Release and referenced stories
- Writes **Shipped Release**
- Moves the Release from `New` to `Active`

After the approved production deployment succeeds, release completion:

- Refuses to complete an empty release
- Closes linked stories
- Closes and stamps the Release work item
- Publishes GitHub Release notes
- Creates the release tag that becomes the next lower boundary

Once a Release is `Closed`, sync does not add new work to it. Bump `package.json` `version` in a
pull request to select the next seeded Release work item. Keep `package-lock.json` synchronized
with the same version.

## 10. Validate release automation

Use a disposable or lab work item and normal pull request:

1. Confirm `package.json` `version` matches an open Release work item.
2. Confirm the previous semver tag is reachable from `main`.
3. Set the story's **Target Release** to the pending version.
4. Create a pull request whose description contains `Ready for Release AB#<id>`.
5. Confirm **PR Work Item Check** passes.
6. Merge the pull request into `main`.
7. Confirm the latest **Deploy** workflow resolves the expected version and tag range.
8. Confirm **ADO Release Sync** creates a Related link and stamps **Shipped Release**.
9. Confirm the story reaches **Ready for Release** through the native Azure Boards integration.
10. Approve the `production` Environment deployment.
11. Confirm **ADO Release Complete** closes the linked story and Release work item.
12. Confirm the GitHub Release and matching tag were created.
13. Confirm **Shipped but Not Closed** returns zero on the Azure DevOps dashboard.

Every push to `main` queues a Deploy workflow. If several pull requests are merged before
production approval, the latest run recomputes the entire `<previous tag>..HEAD` range. Cancel
obsolete queued lab runs and approve the latest one.

## 11. Operate, rerun, and reset the lab

### 11.1 Safe reruns

The provisioning scripts are idempotent and can be rerun:

```powershell
./Provision.ps1 -OrgName <your-org> -Project "Contoso Logistics"
./Verify.ps1 -OrgName <your-org> -Project "Contoso Logistics"
```

Run an individual numbered script when only one resource group needs to be repaired or updated.

### 11.2 Reset Azure DevOps release data

```powershell
./09-Releases.ps1 -OrgName <your-org> -Project "Contoso Logistics" -Reset
```

This operation:

- Removes Release-to-Story links
- Clears **Shipped Release**
- Resets Release work items to `New`
- Clears deployment metadata
- Restores seeded story states and Target Release values

It does not modify GitHub branches, tags, releases, pull requests, or workflow runs.

### 11.3 Reset the GitHub release boundary

Delete the GitHub Release and its tag for the version being reset:

```powershell
gh release delete 1.0.0 --cleanup-tag --yes `
    --repo <owner>/contoso-logistics
```

Move the baseline tag to the current `main` commit:

```powershell
./11-ReleaseBaseline.ps1 -GitHubRepo <owner>/contoso-logistics -Force
```

This creates an empty range for the next lab run without rewriting `main` or force-pushing branch
history.

If the package version was advanced, reset `version` in both `package.json` and
`package-lock.json` to the Release work item you want to test next.

### 11.4 Remove the project

To remove the Azure DevOps side completely, delete the project from
**Project settings > Overview > Delete**. GitHub Environments, repository settings, secrets,
variables, tags, and releases must be removed separately.

## 12. Troubleshooting

### Provisioning cannot authenticate to Azure DevOps

- Run `az login` again with an identity in the same tenant as the Azure DevOps organization.
- Confirm the identity has organization and process administration permissions.
- Pass a bare organization slug or a complete `https://dev.azure.com/<org>` URL.

### The project exists on another process

Use a different `-Project` value, or use `-Force` only when deleting and recreating the project is
acceptable.

### Verify reports missing GitHub Environments

- Run `gh auth status`.
- Confirm the authenticated identity administers the target repository.
- Rerun `10-GitHubEnvironments.ps1`.
- Pass `-GitHubRepo` to `Verify.ps1`.

### Production does not wait for approval

- Confirm `deploy-prod` uses `environment: production`.
- Confirm the production Environment has a required reviewer.
- Check whether the repository visibility and GitHub plan support required reviewers.
- Confirm the deployment branch policy permits `main`.

### Azure Pipeline cannot start

New Azure DevOps organizations may lack Microsoft-hosted parallelism. Request the free grant or
configure a self-hosted agent.

### Teams cannot link to Azure Boards

Confirm Azure DevOps and Teams use the same Entra tenant. Otherwise, use a generic service hook.

### PR Work Item Check passes but release sync finds no story

- Ensure the `AB#` reference reached the commit history.
- Do not rely on a pull request comment as the only reference.
- For squash or merge commits, include the pull request title and description in the result commit.
- For rebase merges, include the reference in a source commit.

### Release sync reports the Release is already closed

The selected version has shipped. Bump `package.json` and `package-lock.json` to the next Release
work item version.

### Release completion skips the release

An empty release cannot be completed. Merge at least one commit containing a resolvable `AB#`
reference, then confirm membership sync linked a story before approving production.

### Release membership uses the wrong work item relationship

Remove hierarchy links and use `System.LinkTypes.Related`. A User Story can have only one hierarchy
parent and should remain parented to its Feature.

### Target Release and Shipped Release disagree

This represents planning drift. Target Release is human intent; Shipped Release is written by
automation from the actual commit range. Review the release sync summary and the release drift
queries before correcting either value.

## 13. Production adaptation checklist

Before adopting these patterns outside the lab:

- Replace the sample deployment jobs with real deployment and rollback procedures.
- Prefer GitHub OIDC and an Entra service principal over a shared PAT.
- Apply least-privilege repository, Azure DevOps, and environment permissions.
- Protect `main` and require the PR Work Item Check through rulesets.
- Define secret rotation, audit, break-glass, and incident response procedures.
- Pin and version centrally managed reusable workflows.
- Validate retention and compliance requirements for work items, workflow logs, and releases.
- Monitor failed membership or completion summaries because work-tracking automation is
  intentionally non-blocking.

For multi-repository rollout guidance, including reusable workflow templates and organization-level
variables, see [`release-automation-guide.md`](release-automation-guide.md).

## 14. Further reading

- [Provisioner reference](../provision/README.md)
- [Release automation integration guide](release-automation-guide.md)
- [Customize an inherited process](https://learn.microsoft.com/azure/devops/organizations/settings/work/manage-process)
- [Configure and customize Azure Boards](https://learn.microsoft.com/azure/devops/boards/configure-customize)
- [Areas and iteration paths](https://learn.microsoft.com/azure/devops/organizations/settings/about-areas-iterations)
- [Delivery Plans](https://learn.microsoft.com/azure/devops/boards/plans/review-team-plans)
- [Service hooks](https://learn.microsoft.com/azure/devops/service-hooks/overview)
- [Azure Boards for Microsoft Teams](https://learn.microsoft.com/azure/devops/boards/integrations/boards-teams)
- [GitHub Environments](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Reusable workflows](https://docs.github.com/actions/using-workflows/reusing-workflows)
- [Repository rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)