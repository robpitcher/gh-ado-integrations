<#
  Verify.ps1 — Confirm the provisioned ADO environment matches expectations.
  Prints a pass/fail line per check.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),
    [string]$GitHubRepo   # optional — checks GitHub Environments if supplied (owner/repo)
)
. "$PSScriptRoot/Common.ps1"

$ok = New-Object System.Collections.Generic.List[string]
$bad = New-Object System.Collections.Generic.List[string]
function Check { param([bool]$Cond, [string]$Label) if ($Cond) { $ok.Add($Label) } else { $bad.Add($Label) } }

# Process: Contoso Agile exists as an inherited process.
$AgileTypeId = 'adcc42ab-9882-485e-a3ed-7678f01f66bc'
$procs = (Invoke-Ado GET (Get-CoreUrl 'work/processes')).value
$proc = $procs | Where-Object { $_.name -eq 'Contoso Agile' } | Select-Object -First 1
Check ([bool]$proc) "process 'Contoso Agile' exists"
if ($proc) {
    Check ($proc.parentProcessTypeId -eq $AgileTypeId -or $proc.customizationType -eq 'inherited') "process 'Contoso Agile' inherits from Agile"
}

# Release-tracking process customizations: User Story fields, Release WIT/states/fields
if ($proc) {
    $procId = $proc.typeId
    $usWit = ((Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workitemtypes")).value |
        Where-Object { $_.name -eq 'User Story' -and $_.customization -eq 'inherited' } | Select-Object -First 1).referenceName
    if ($usWit) {
        $usStates = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$usWit/states")).value
        $readyState = $usStates | Where-Object { $_.name -eq 'Ready for Release' } | Select-Object -First 1
        Check ([bool]$readyState) "User Story state 'Ready for Release'"
        if ($readyState) {
            Check ($readyState.stateCategory -eq 'Resolved') "'Ready for Release' is in the Resolved category"
        }

        $usFields = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$usWit/fields")).value.name
        foreach ($f in @('Target Release','Shipped Release')) { Check ($usFields -contains $f) "User Story field '$f'" }

        $layout = Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$usWit/layout")
        $onForm = @{}
        foreach ($pg in $layout.pages) { foreach ($sec in $pg.sections) { foreach ($g in $sec.groups) { foreach ($c in $g.controls) {
            if ($c.id -in @('Custom.TargetRelease','Custom.ShippedRelease')) { $onForm[$c.id] = $true } } } } }
        Check ($onForm.ContainsKey('Custom.TargetRelease')) "'Target Release' on User Story form"
        Check ($onForm.ContainsKey('Custom.ShippedRelease')) "'Shipped Release' on User Story form"
    }

    $releaseWit = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workitemtypes")).value | Where-Object { $_.name -eq 'Release' } | Select-Object -First 1
    Check ([bool]$releaseWit) "WIT 'Release' exists"
    if ($releaseWit) {
        $relRef = $releaseWit.referenceName
        $relStates = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$relRef/states")).value.name
        foreach ($s in @('New','Active','Closed')) { Check ($relStates -contains $s) "Release state '$s'" }
        $relFields = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$relRef/fields")).value.name
        foreach ($f in @('Release Version','Release Branch','Deployed On','Deployed By','Release Notes URL')) { Check ($relFields -contains $f) "Release field '$f'" }

        $relLayout = Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$relRef/layout")
        $relVersionOnForm = $false
        foreach ($pg in $relLayout.pages) { foreach ($sec in $pg.sections) { foreach ($g in $sec.groups) { foreach ($c in $g.controls) {
            if ($c.id -eq 'Custom.ReleaseVersion') { $relVersionOnForm = $true } } } } }
        Check $relVersionOnForm "'Release Version' on Release form"

        $relRules = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$relRef/rules")).value
        $hasRequiredRule = [bool]($relRules | Where-Object {
            $_.actions | Where-Object { $_.actionType -eq 'makeRequired' -and $_.targetField -eq 'Custom.ReleaseVersion' }
        } | Select-Object -First 1)
        Check $hasRequiredRule "'Release Version' has a required rule"

        # Release must NOT be on any backlog level — a WIT gets a backlog level via a
        # 'portfolio'/'requirement'/'task' behavior association; an empty list means
        # it isn't parented into any backlog. A failed query is NOT the same as an
        # empty list — treat it as an unverified/failed check rather than a silent
        # pass, since it could just as easily mean the endpoint changed.
        $behaviors = @()
        $behaviorsQueryFailed = $false
        try { $behaviors = (Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypesBehaviors/$relRef/behaviors")).value }
        catch { $behaviorsQueryFailed = $true }
        if ($behaviorsQueryFailed) {
            Check $false "'Release' is not on any backlog level (could not verify — behaviors query failed)"
        } else {
            Check (@($behaviors).Count -eq 0) "'Release' is not on any backlog level"
        }
    }
}

# Teams
$projId = Get-ProjectId
$teams = (Invoke-Ado GET (Get-CoreUrl "projects/$projId/teams")).value.name
foreach ($t in @('App Team', 'QA Team', 'DevOps Team')) { Check ($teams -contains $t) "team '$t'" }

# Area paths
$areas = (Invoke-Ado GET (Get-ProjUrl 'wit/classificationnodes/areas?$depth=1')).children.name
foreach ($a in @('App', 'QA', 'DevOps')) { Check ($areas -contains $a) "area path '$a'" }

# Iterations
$iters = (Invoke-Ado GET (Get-ProjUrl 'wit/classificationnodes/iterations?$depth=1')).children.name
foreach ($s in @('Sprint 1','Sprint 2','Sprint 3')) { Check ($iters -contains $s) "sprint '$s'" }

# Shared queries
$qnames = (Invoke-Ado GET (Get-ProjUrl 'wit/queries/Shared%20Queries?$depth=2&$expand=all')).children.name
foreach ($q in @(
    'All Stories','App Team Stories','QA Team Stories','DevOps Stories','Active Stories','Ready for Release Stories',
    'Release Contents - 1.0.0','Release Contents - 1.1.0','Release Contents - 1.2.0',
    'Release Drift - 1.0.0','Release Drift - 1.1.0','Release Drift - 1.2.0',
    'Targeted 1.0.0 - Not Yet Shipped','Targeted 1.1.0 - Not Yet Shipped','Targeted 1.2.0 - Not Yet Shipped',
    'Shipped but Not Closed','Release Register'
)) {
    Check ($qnames -contains $q) "query '$q'"
}

# Project-scoped story count (18 logistics + 16 DevOps = 34)
$res = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='User Story'" }
$n = @($res.workItems).Count
Check ($n -eq 34) "project-scoped story count = $n (expected 34)"
if ($n -gt 0) {
    $storyIds = @($res.workItems | ForEach-Object { $_.id })
    $storyItems = (Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($storyIds -join ',')&fields=System.Title,System.State,Custom.TargetRelease")).value
    $storyByTitle = @{}
    foreach ($story in $storyItems) { $storyByTitle[$story.fields.'System.Title'] = $story }

    $active100Stories = @(
        'Track shipment location on a live map',
        'Suggest optimal bin on receipt',
        'Set up build and unit-test pipeline',
        'Add pipeline status badge to repo README',
        'Enable secret scanning in CI pipeline'
    )
    foreach ($title in $active100Stories) {
        $story = $storyByTitle[$title]
        Check ([bool]$story) "baseline story '$title' exists"
        if ($story) {
            Check ($story.fields.'System.State' -eq 'Active') "baseline story '$title' is Active"
            Check ($story.fields.'Custom.TargetRelease' -eq '1.0.0') "baseline story '$title' targets 1.0.0"
        }
    }

    $readyStories = @(
        'Show estimated delivery window',
        'Surface delivery exceptions',
        'Validate putaway with handheld scan',
        'Reslot slow-moving SKUs nightly',
        'Add automated deploy to staging',
        'Add dependency and container vulnerability scanning'
    )
    foreach ($title in $readyStories) {
        $story = $storyByTitle[$title]
        Check ([bool]$story) "seeded story '$title' exists"
        if ($story) {
            Check ($story.fields.'System.State' -eq 'Ready for Release') "seeded story '$title' is Ready for Release"
        }
    }
}

# Delivery plan
$plans = (Invoke-Ado GET (Get-ProjUrl 'work/plans')).value.name
Check ($plans -contains 'Contoso Roadmap') "delivery plan 'Contoso Roadmap'"

# Dashboard: tiles + charts
$teamId = (Invoke-Ado GET (Get-CoreUrl "projects/$projId")).defaultTeam.id
$proj = [uri]::EscapeDataString($script:Project)
$dl = "$script:OrgUrl/$proj/$teamId/_apis/dashboard/dashboards?api-version=7.1-preview.3"
foreach ($d in (Invoke-Ado GET $dl).value) {
    if ($d.name -eq 'Contoso Delivery') {
        $full = Invoke-Ado GET "$script:OrgUrl/$proj/$teamId/_apis/dashboard/dashboards/$($d.id)?api-version=7.1-preview.3"
        $scalars = @($full.widgets | Where-Object { $_.contributionId -match 'QueryScalarWidget' })
        $charts  = @($full.widgets | Where-Object { $_.contributionId -match 'WitChartWidget' })
        Check ($scalars.Count -ge 5 -and $charts.Count -ge 4) "dashboard ($($scalars.Count) tiles, $($charts.Count) charts)"
    }
}

# Release work items: baseline is 3 Release items in New with expected versions,
# and ZERO Release<->Story links / ZERO non-empty Shipped Release values. A dirty
# environment (mid-demo or forgotten reset) should fail here with a hint to run -Reset.
$relWiql = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='Release'" }
$relIds = @($relWiql.workItems | ForEach-Object { $_.id })
$expectedReleases = @{
    '1.0.0' = @{ version = '1.0.0' }
    '1.1.0' = @{ version = '1.1.0' }
    '1.2.0' = @{ version = '1.2.0' }
}
$relItems = @()
if ($relIds.Count -gt 0) { $relItems = (Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($relIds -join ',')&`$expand=all")).value }
Check ($relItems.Count -eq 3) "3 Release work items exist ($($relItems.Count) found)"
foreach ($title in $expectedReleases.Keys) {
    $wi = $relItems | Where-Object { $_.fields.'System.Title' -eq $title } | Select-Object -First 1
    Check ([bool]$wi) "Release '$title' exists"
    if ($wi) {
        Check ($wi.fields.'System.State' -eq 'New') "Release '$title' is in New (dirty? try 09-Releases.ps1 -Reset)"
        Check ($wi.fields.'Custom.ReleaseVersion' -eq $expectedReleases[$title].version) "Release '$title' version = $($expectedReleases[$title].version)"
    }
}
$relLinkCount = 0
foreach ($wi in $relItems) { if ($wi.relations) { $relLinkCount += @($wi.relations | Where-Object { $_.rel -like 'System.LinkTypes.*' }).Count } }
Check ($relLinkCount -eq 0) "baseline has zero Release<->Story links (dirty? try 09-Releases.ps1 -Reset)"

$shippedWiql = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='User Story' AND [Custom.ShippedRelease] <> ''" }
Check (@($shippedWiql.workItems).Count -eq 0) "baseline has zero non-empty Shipped Release values (dirty? try 09-Releases.ps1 -Reset)"

# package.json's version is what selects the pending Release work item at deploy
# time (see .github/workflows/ado-release-sync.yml release lookup), so a
# version that matches no Release means the sync would auto-create a stray one.
$pkgPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'package.json'
if (Test-Path $pkgPath) {
    $pkgVersion = (Get-Content $pkgPath -Raw | ConvertFrom-Json).version
    Check ($expectedReleases.Values.version -contains $pkgVersion) "package.json version '$pkgVersion' matches a Release work item (pending release)"
}

# Optional pipeline
$pls = (Invoke-Ado GET (Get-ProjUrl 'pipelines' '7.1-preview.1')).value.name
if ($pls -contains 'contoso-logistics-ci') { $ok.Add("pipeline 'contoso-logistics-ci' (optional)") }
else { Write-Host "  note: pipeline not set up (run 08-Pipeline.ps1 to add it)" }

# Optional GitHub Environments (soft-fail — never blocks the overall check)
if ($GitHubRepo) {
    try {
        $ghTok = (gh auth token 2>$null)
        if ($ghTok) {
            $ghHeaders = @{ Authorization = "Bearer $($ghTok.Trim())"; Accept = 'application/vnd.github+json' }
            $envs = (Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/$GitHubRepo/environments" -Headers $ghHeaders).environments.name
            foreach ($e in @('dev','stage','production')) {
                if ($envs -contains $e) { $ok.Add("GitHub environment '$e' (optional)") }
                else { Write-Host "  note: GitHub environment '$e' not found (run 10-GitHubEnvironments.ps1 to add it)" }
            }
            if ($envs -contains 'production') {
                $prodEnv = Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/$GitHubRepo/environments/production" -Headers $ghHeaders
                if (@($prodEnv.protection_rules | Where-Object { $_.type -eq 'required_reviewers' }).Count -gt 0) { $ok.Add("GitHub environment 'production' has a required reviewer (optional)") }
                else { Write-Host "  note: GitHub environment 'production' has no required reviewer configured (plan tier, or run 10-GitHubEnvironments.ps1)" }

                # Deploys run from main now, so a leftover release/* policy would
                # reject every production deployment this lab produces.
                try {
                    $policies = @((Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/$GitHubRepo/environments/production/deployment-branch-policies" -Headers $ghHeaders).branch_policies.name)
                    if ($policies -contains 'release/*') { Write-Host "  note: GitHub environment 'production' still restricts deployments to 'release/*' — re-run 10-GitHubEnvironments.ps1 so main can deploy" }
                    elseif ($policies -contains 'main') { $ok.Add("GitHub environment 'production' allows deployments from main (optional)") }
                } catch { }
            }

            # The baseline tag bounds the first release's commit range. Without it,
            # ado-release-sync.yml falls back to the entire repo history.
            try {
                Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/$GitHubRepo/git/ref/tags/0.9.0" -Headers $ghHeaders | Out-Null
                $ok.Add("release baseline tag '0.9.0' (optional)")
            } catch { Write-Host "  note: release baseline tag '0.9.0' not found (run 11-ReleaseBaseline.ps1 to add it)" }
        } else { Write-Host "  note: 'gh auth token' unavailable — skipping GitHub Environments check" }
    } catch { Write-Host "  note: could not query GitHub Environments for $GitHubRepo — $($_.Exception.Message)" }
} else {
    Write-Host "  note: pass -GitHubRepo owner/repo to also verify GitHub Environments"
}

Write-Host "`nPASS ($($ok.Count)):"
$ok | ForEach-Object { Write-Host "  ok   $_" }
if ($bad.Count) {
    Write-Host "`nFAIL ($($bad.Count)):" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "  BAD  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "`nALL CHECKS PASSED" -ForegroundColor Green
