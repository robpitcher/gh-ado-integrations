<#
  New-DemoPullRequest.ps1 — drive the real thing: for each User Story targeted at a
  release, open an actual pull request that is attached to that actual work item,
  and (optionally) merge it.

  Why this replaces Get-DemoCommits.ps1 as the primary path: that script fabricates
  empty commits with AB#<id> in the message, which is not how the work reaches the
  branch in real life and skips everything interesting — the pull request, the work
  item link, the PR work item check, the merge. Audiences need to see the loop they
  actually live in. Get-DemoCommits.ps1 is kept as an offline shortcut when you only
  need commits on a branch fast.

  Deliberate choice — "Ready for Release AB#<id>" goes in the PULL REQUEST, not
  the commit message. The Azure Boards GitHub integration uses that exact state
  name to transition the story when the PR merges, while the AB# reference also
  exercises the detection paths in .github/workflows/pr-workitem-check.yml and
  .github/workflows/ado-release-sync.yml. It depends on the repository's
  squash-merge setting carrying the PR description into the squash commit, which
  this script configures unless you pass -SkipRepoSettings.

  Everything happens in a TEMPORARY CLONE under $env:TEMP, never in your working
  tree, so a demo can't leave you on a stray branch with uncommitted edits.

  ORDER MATTERS, but not the way it used to. These pull requests target MAIN, like
  any ordinary change. Release membership is derived from the commits between the
  previous release tag and HEAD (see .github/workflows/ado-release-sync.yml),
  so what matters is that a baseline tag exists BEFORE these merges land — run
  provision/11-ReleaseBaseline.ps1 first, or the range falls back to the whole
  history of the repository and historical AB# references can be attributed to
  the current release.

  Scope note: this is the BULK filler. The intended demo shape (see LAB-GUIDE.md
  §8.4) is to walk ONE story by hand — assign it to the release, implement its
  stubbed service function, open the PR, watch the check, merge — and then run this
  to populate the rest of the release so the dashboard has something to count. Pass
  the hand-walked story to -Skip so it isn't duplicated.

  Every merge into main pushes it, and deploy.yml triggers on `push: main`, so a
  run with -Merge queues one Deploy run per pull request. That's expected: cancel
  the intermediate runs and approve production on the last one, which is the one
  whose commit range contains the whole release.

  Examples:
    # See what would happen, change nothing:
    ./New-DemoPullRequest.ps1 -OrgUrl https://dev.azure.com/<org> -Release '1.0.0' `
        -GitHubRepo <owner>/contoso-logistics -DryRun

    # Open PRs for every story in the release except the one you demoed live, and merge them:
    ./New-DemoPullRequest.ps1 -OrgUrl https://dev.azure.com/<org> -Release '1.0.0' `
        -GitHubRepo <owner>/contoso-logistics -Skip 'Retry failed carrier callbacks' -Merge
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),

    # Must exactly match the Custom.TargetRelease value on the stories, e.g. '1.0.0'.
    # It's a plain-text field, so a typo here matches nothing rather than erroring.
    [Parameter(Mandatory)][string]$Release,

    # owner/name. Defaults to whatever `gh repo view` resolves for the current directory.
    [string]$GitHubRepo,

    # What the pull requests target. Defaults to main: story pull requests land on
    # the trunk like any ordinary change, and a release is the span between two
    # tags rather than the contents of a branch.
    [string]$BaseBranch = 'main',

    # Story titles and/or work item ids to leave alone — use this for the story you
    # walked through by hand.
    [string[]]$Skip = @(),

    # Cap how many pull requests to open. 0 = no cap.
    [int]$Limit = 0,

    # Squash-merge each pull request after opening it.
    [switch]$Merge,

    # Don't touch the repository's merge-commit settings.
    [switch]$SkipRepoSettings,

    [switch]$DryRun
)
. "$PSScriptRoot/Common.ps1"

$ErrorActionPreference = 'Stop'
# Pinned explicitly: when this is $true a non-zero exit from a native command
# throws before Invoke-Native can inspect $LASTEXITCODE, which would defeat
# -AllowFailure. It defaults to $false today, but it's a preference a profile or
# a future default can flip.
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$Args, [switch]$AllowFailure)
    $output = & $Exe @Args 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "$Exe $($Args -join ' ') failed (exit $LASTEXITCODE):`n$($output -join "`n")"
    }
    return $output
}

function ConvertTo-Slug {
    param([string]$Text)
    $s = ($Text -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    if ($s.Length -gt 48) { $s = $s.Substring(0, 48).Trim('-') }
    return $s
}

# ---- Preconditions ----------------------------------------------------------

foreach ($tool in 'git', 'gh') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "'$tool' is required but not on PATH." }
}
Invoke-Native gh @('auth', 'status') | Out-Null

if (-not $GitHubRepo) {
    $GitHubRepo = (Invoke-Native gh @('repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner')) -join ''
    $GitHubRepo = $GitHubRepo.Trim()
}
if (-not $GitHubRepo) { throw 'Could not determine the GitHub repository — pass -GitHubRepo <owner>/<name>.' }
Write-Host "GitHub repository: $GitHubRepo"

$releaseSlug = ConvertTo-Slug $Release
Write-Host "Pull request base: $BaseBranch"

# ---- 1. Stories targeted at this release ------------------------------------

$safeRelease = $Release -replace "'", "''"
$wiql = @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='User Story' AND [Custom.TargetRelease]='$safeRelease' ORDER BY [System.Id]" }
$ids = @((Invoke-Ado POST (Get-ProjUrl 'wit/wiql') $wiql).workItems | ForEach-Object { $_.id })

if ($ids.Count -eq 0) {
    Write-Warning "No User Stories have Custom.TargetRelease = '$Release'. Nothing to do."
    return
}

$stories = @((Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($ids -join ',')")).value | ForEach-Object {
    [pscustomobject]@{ Id = [int]$_.id; Title = [string]$_.fields.'System.Title' }
})

$skipSet = @{}
foreach ($s in $Skip) { $skipSet[$s.Trim().ToLowerInvariant()] = $true }
$stories = @($stories | Where-Object { -not ($skipSet.ContainsKey($_.Title.ToLowerInvariant()) -or $skipSet.ContainsKey("$($_.Id)") -or $skipSet.ContainsKey("ab#$($_.Id)")) })

if ($Limit -gt 0 -and $stories.Count -gt $Limit) { $stories = $stories[0..($Limit - 1)] }

if ($stories.Count -eq 0) {
    Write-Warning "Every story targeted at '$Release' was excluded by -Skip/-Limit. Nothing to do."
    return
}

Write-Host "Stories targeted at '$Release' (after -Skip/-Limit): $($stories.Count)"
$stories | ForEach-Object { Write-Host "  AB#$($_.Id) $($_.Title)" }

if ($DryRun) {
    Write-Host ''
    Write-Host 'DryRun: no branches, commits, pull requests or repository settings were changed.'
    return
}

# ---- 2. Repository merge settings -------------------------------------------
# The whole point of the demo is that AB#<id> lives on the pull request, not in the
# commit message. GitHub's default squash message is the list of source commit
# messages, so without this the reference never reaches the squash commit that
# ado-release-sync.yml reads. That workflow does not query pull request metadata,
# so this setting is what carries the reference into commit history.
if (-not $SkipRepoSettings) {
    try {
        Invoke-Native gh @('api', '-X', 'PATCH', "repos/$GitHubRepo",
            '-f', 'squash_merge_commit_title=PR_TITLE',
            '-f', 'squash_merge_commit_message=PR_BODY') | Out-Null
        Write-Host 'Repository squash-merge message set to "pull request title and description".'
    }
    catch {
        Write-Warning "Could not update the repository merge settings (admin permission required): $($_.Exception.Message)"
        Write-Warning 'Set Settings -> Pull Requests -> Default commit message -> "Pull request title and description" by hand, or pass -SkipRepoSettings.'
    }
}

# ---- 3. Temporary clone ------------------------------------------------------

$work = Join-Path ([IO.Path]::GetTempPath()) "contoso-demo-pr-$([guid]::NewGuid().ToString('n').Substring(0,8))"
Write-Host "Cloning $GitHubRepo into $work ..."
Invoke-Native gh @('repo', 'clone', $GitHubRepo, $work, '--', '--quiet') | Out-Null

$created = @()
try {
    Invoke-Native git @('-C', $work, 'ls-remote', '--exit-code', '--heads', 'origin', $BaseBranch) -AllowFailure | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Base branch '$BaseBranch' does not exist on $GitHubRepo."
    }
    Invoke-Native git @('-C', $work, 'switch', $BaseBranch) | Out-Null

    foreach ($story in $stories) {
        $storySlug = ConvertTo-Slug $story.Title
        $branch = "demo/ab-$($story.Id)-$storySlug"

        # Re-runnable: an existing branch means this story already has a PR.
        Invoke-Native git @('-C', $work, 'ls-remote', '--exit-code', '--heads', 'origin', $branch) -AllowFailure | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  skip AB#$($story.Id) — branch '$branch' already exists on the remote."
            continue
        }

        Invoke-Native git @('-C', $work, 'switch', '-C', $branch, $BaseBranch) | Out-Null

        # One file per story, never a shared one: every branch is cut from the same
        # base, so a shared file would make each pull request an add/add conflict
        # against the one merged before it and only the first would go in.
        $notePath = Join-Path $work (Join-Path 'docs' (Join-Path 'changelog' (Join-Path $releaseSlug "ab-$($story.Id)-$storySlug.md")))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $notePath) | Out-Null
        Set-Content -Path $notePath -Encoding utf8 -Value @(
            "# $($story.Title)"
            ''
            "Shipped in **$Release**. Tracked as AB#$($story.Id)."
        )

        Invoke-Native git @('-C', $work, 'add', '--all') | Out-Null
        # NOTE: no AB# here, on purpose. See the header.
        Invoke-Native git @('-C', $work, 'commit', '-m', "chore: record `"$($story.Title)`" in the $Release changelog") | Out-Null
        Invoke-Native git @('-C', $work, 'push', '--quiet', '-u', 'origin', $branch) | Out-Null

        $body = @(
            "Implements the **$($story.Title)** story."
            ''
            "Ready for Release AB#$($story.Id)"
            ''
            '_Note: Azure Boards moves this story to Ready for Release when the PR merges. The reference is deliberately only in this description, not in the commit message._'
        ) -join "`n"

        $prUrl = (Invoke-Native gh @('pr', 'create', '--repo', $GitHubRepo, '--base', $BaseBranch, '--head', $branch,
            '--title', $story.Title, '--body', $body)) -join "`n"
        Write-Host "  + AB#$($story.Id) $($story.Title) -> $($prUrl.Trim())"
        $created += [pscustomobject]@{ Id = $story.Id; Title = $story.Title; Branch = $branch; Url = $prUrl.Trim() }
    }

    if ($Merge) {
        Write-Host ''
        Write-Host 'Merging...'
        foreach ($pr in $created) {
            # GitHub computes mergeability asynchronously; merging the instant after
            # creating the PR gets "not mergeable" for a state it hasn't decided yet.
            for ($i = 0; $i -lt 10; $i++) {
                $state = (Invoke-Native gh @('pr', 'view', $pr.Branch, '--repo', $GitHubRepo, '--json', 'mergeable', '--jq', '.mergeable') -AllowFailure) -join ''
                if ($state.Trim() -in 'MERGEABLE', 'CONFLICTING') { break }
                Start-Sleep -Seconds 2
            }

            $out = Invoke-Native gh @('pr', 'merge', $pr.Branch, '--repo', $GitHubRepo, '--squash', '--delete-branch') -AllowFailure
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  could not merge AB#$($pr.Id) ($($pr.Url)) — merge it in the UI. $($out -join "`n")"
            } else {
                Write-Host "  merged AB#$($pr.Id) $($pr.Title)"
            }
        }
    }
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Done. $($created.Count) pull request(s) opened$(if ($Merge) { ' and merged' }) against $BaseBranch."
if (-not $Merge -and $created.Count -gt 0) {
    Write-Host 'Merge them (UI or `gh pr merge --squash`) to put them in the release.'
}
