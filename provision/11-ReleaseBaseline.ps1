<#
  11-ReleaseBaseline.ps1 — Seed (or move) the baseline tag that bounds the first
  release.

  Release membership is derived from a commit range, not from a branch:
  .github/workflows/ado-release-sync.yml computes
  `<previous release tag>..HEAD` on main. Every release after the first one gets
  its lower bound for free, because completing a release publishes a GitHub
  Release and therefore a tag. The FIRST release has no predecessor, so without a
  baseline tag the range is the entire history of the repository and historical
  AB# references can be attributed to the current release.

  This script plants that first boundary. The default tag is one minor version
  below the first seeded release (0.9.0 vs. 1.0.0), so it reads as "the
  release before 1.0.0" rather than as an arbitrary marker.

  It is also the demo RESET mechanism. Story pull requests now land on main, so a
  demo leaves commits there — but nothing needs rewriting, because -Force simply
  re-points the baseline tag at the current tip of main. The next run's range
  starts from there. NEVER force-push main to reset this lab.

  Like 10-GitHubEnvironments.ps1 this targets GitHub, not Azure DevOps, so it
  authenticates with `gh auth token` and calls the GitHub REST API directly — no
  local clone and no `az login` required.

  Idempotent: creating a tag that already points at the requested commit is a
  no-op, and -Force is needed to move one that points somewhere else.

  Examples:
    ./11-ReleaseBaseline.ps1 -GitHubRepo myuser/contoso-logistics
    ./11-ReleaseBaseline.ps1 -GitHubRepo myuser/contoso-logistics -Force   # reset between demos
    ./11-ReleaseBaseline.ps1 -GitHubRepo myuser/contoso-logistics -Delete
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$GitHubRepo,   # owner/repo
    [string]$Tag = '0.9.0', # semver boundary tag; supports 1.2.3 and v1.2.3
    [string]$Ref = 'main',                        # branch, tag or sha the baseline should point at
    [switch]$Force,                               # move the tag if it already exists elsewhere
    [switch]$Delete
)
$ErrorActionPreference = 'Stop'

# Must agree with the semver boundary check in .github/workflows/ado-release-sync.yml.
# A tag that doesn't match is silently ignored as a release boundary, which would
# leave the range unbounded with no obvious cause — so reject it here instead.
# Common caller mistake: repo value accidentally passed to -Tag.
if ($Tag -match '^[^/\s]+/[^/\s]+$') {
    throw "Tag '$Tag' looks like a GitHub repo. Pass -GitHubRepo owner/repo and use -Tag for a semver boundary tag like '0.9.0' or 'v0.9.0'."
}

if ($Tag -notmatch '^v?\d+\.\d+\.\d+$') {
    throw "Baseline tag '$Tag' is not semver-shaped (e.g. '0.9.0' or 'v0.9.0'). ado-release-sync.yml only accepts tags matching '^v?\d+\.\d+\.\d+$' as release boundaries."
}

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

# $null when the tag doesn't exist, rather than throwing — "not there yet" is the
# normal first-run state, not an error.
function Get-TagRef {
    try { return Invoke-Gh GET "/repos/$GitHubRepo/git/ref/tags/$Tag" }
    catch { return $null }
}

$existing = Get-TagRef

if ($Delete) {
    if (-not $existing) { Write-Host "Baseline tag '$Tag' does not exist on $GitHubRepo — nothing to delete."; return }
    Invoke-Gh DELETE "/repos/$GitHubRepo/git/refs/tags/$Tag" | Out-Null
    Write-Host "  - deleted baseline tag: $Tag"
    Write-Host 'Done.'
    return
}

$targetSha = (Invoke-Gh GET "/repos/$GitHubRepo/commits/$Ref").sha
Write-Host "Baseline tag for ${GitHubRepo}:"
Write-Host "  $Ref -> $targetSha"

if (-not $existing) {
    Invoke-Gh POST "/repos/$GitHubRepo/git/refs" @{ ref = "refs/tags/$Tag"; sha = $targetSha } | Out-Null
    Write-Host "  + created baseline tag: $Tag"
}
elseif ($existing.object.sha -eq $targetSha) {
    Write-Host "  baseline tag already at the right commit: $Tag"
}
elseif ($Force) {
    Invoke-Gh PATCH "/repos/$GitHubRepo/git/refs/tags/$Tag" @{ sha = $targetSha; force = $true } | Out-Null
    Write-Host "  ~ moved baseline tag: $Tag ($($existing.object.sha.Substring(0,7)) -> $($targetSha.Substring(0,7)))"
}
else {
    Write-Warning "Baseline tag '$Tag' exists at $($existing.object.sha.Substring(0,7)) but $Ref is at $($targetSha.Substring(0,7)). Re-run with -Force to move it (that is the normal reset between demos)."
}

Write-Host 'Done.'
