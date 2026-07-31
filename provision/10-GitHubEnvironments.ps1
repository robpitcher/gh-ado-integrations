<#
  10-GitHubEnvironments.ps1 — Provision GitHub Environments (dev, stage, production)
  on the demo repo, with a required-reviewer approval gate on 'production'.

  This is the first provisioning script that targets GitHub rather than Azure
  DevOps: it uses `gh auth token` for auth and calls the GitHub REST API directly.
  The approval gate on 'production' is the pivot point of the whole release-tracking
  scenario — it's the moment a release genuinely becomes "shipped", and it's the
  event the work-item automation (see .github/workflows/deploy.yml) hangs off.

  Idempotent: environments are upserted via PUT; branch policies are checked before
  creation since that endpoint is not itself idempotent.

  Example:
    ./10-GitHubEnvironments.ps1 -GitHubRepo myuser/contoso-logistics
#>
param(
    [Parameter(Mandatory)][string]$GitHubRepo,   # owner/repo
    [string]$Reviewer,                            # defaults to the authenticated user
    [int]$WaitTimer = 0
)
$ErrorActionPreference = 'Stop'

function Get-GhToken {
    $tok = (gh auth token 2>$null)
    if (-not $tok) { throw "Could not get a GitHub token via 'gh auth token'. Run 'gh auth login' first." }
    return $tok.Trim()
}

$script:GhHeaders = @{
    Authorization = "Bearer $(Get-GhToken)"
    Accept        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$script:GhApi = 'https://api.github.com'

function Invoke-Gh {
    param([Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][string]$Path, $Body)
    $params = @{ Method = $Method; Uri = "$script:GhApi$Path"; Headers = $script:GhHeaders; ContentType = 'application/json' }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
    try { return Invoke-RestMethod @params }
    catch {
        $detail = $_.ErrorDetails.Message
        throw "GitHub $Method $Path failed: $($_.Exception.Message)`n$detail"
    }
}

function Get-ReviewerId {
    param([string]$Login)
    if ($Login) { return (Invoke-Gh GET "/users/$Login").id }
    return (Invoke-Gh GET '/user').id
}

# The Environments API requires *admin* on the repo, and GitHub answers a
# non-admin token with 404 rather than 403 (it won't confirm the repo exists to
# someone who can't administer it). Check up front so the failure names the real
# cause instead of looking like a missing repo.
function Assert-RepoAdmin {
    $repo = $null
    try { $repo = Invoke-Gh GET "/repos/$GitHubRepo" }
    catch {
        $who = try { (Invoke-Gh GET '/user').login } catch { '<unknown>' }
        throw "Repo '$GitHubRepo' is not visible to the authenticated GitHub account ('$who'). Check the owner/repo spelling, that the repo exists, and that this account has access. Switch accounts with 'gh auth switch'."
    }
    if (-not $repo.permissions.admin) {
        $who = $repo.permissions | Out-String
        throw ("Account '$((Invoke-Gh GET '/user').login)' does not have admin on '$GitHubRepo' (permissions:$who). " +
               "The GitHub Environments API requires admin and returns 404 without it. Ask an org owner for admin, or run 'gh auth switch' to an account that has it.")
    }
}

function Set-Environment {
    param([string]$Name, [hashtable]$Body = @{})
    Invoke-Gh PUT "/repos/$GitHubRepo/environments/$Name" $Body | Out-Null
    Write-Host "  + environment: $Name"
}

function Set-ProductionGate {
    param([int]$ReviewerId)
    $body = @{
        reviewers = @(@{ type = 'User'; id = $ReviewerId })
        # A user cannot approve their own deployment when "prevent self-review" is
        # on. Leave it off deliberately so a single operator can run the whole demo
        # solo (approve their own production deployment).
        prevent_self_review = $false
    }
    if ($WaitTimer -gt 0) { $body.wait_timer = $WaitTimer }
    try {
        Invoke-Gh PUT "/repos/$GitHubRepo/environments/production" $body | Out-Null
        Write-Host "  + environment: production (required reviewer id=$ReviewerId, wait_timer=$WaitTimer)"
    } catch {
        # Required reviewers on a private repo need GitHub Pro/Team/Enterprise. Don't
        # fail the whole provisioning run over a plan-tier limit — the lab should
        # still be usable, just without the approval gate.
        Write-Warning "Could not set a required reviewer on 'production' (likely a plan-tier limit on a private repo). Environment created WITHOUT the approval gate. Error: $($_.Exception.Message)"
        Set-Environment 'production' @{}
    }
}

function Set-ProductionBranchPolicy {
    Invoke-Gh PUT "/repos/$GitHubRepo/environments/production" @{ deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true } } | Out-Null
    $existing = $null
    try { $existing = (Invoke-Gh GET "/repos/$GitHubRepo/environments/production/deployment-branch-policies").branch_policies } catch { $existing = @() }

    # Releases ship from main (see .github/workflows/deploy.yml) — a release/* policy
    # here would reject every production deployment the lab produces. Clean up that
    # older policy if this repo was provisioned before the switch.
    foreach ($stale in @($existing | Where-Object { $_.name -eq 'release/*' })) {
        Invoke-Gh DELETE "/repos/$GitHubRepo/environments/production/deployment-branch-policies/$($stale.id)" | Out-Null
        Write-Host '  - branch policy: removed stale release/*'
    }

    if ($existing | Where-Object { $_.name -eq 'main' }) {
        Write-Host '  branch policy exists: main'
        return
    }
    Invoke-Gh POST "/repos/$GitHubRepo/environments/production/deployment-branch-policies" @{ name = 'main' } | Out-Null
    Write-Host '  + branch policy: production restricted to main'
}

Write-Host "GitHub environments for $GitHubRepo :"
Assert-RepoAdmin
Set-Environment 'dev'
Set-Environment 'stage'
$reviewerId = Get-ReviewerId $Reviewer
Set-ProductionGate $reviewerId
Set-ProductionBranchPolicy
Write-Host 'Done.'
