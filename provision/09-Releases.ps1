<#
  09-Releases.ps1 - Seed Release work items as clean, empty containers, and provide
  a -Reset switch that restores the demo baseline between audiences.

  Baseline (clean, neutral): three Release work items exist in 'New' with their
  version set. Nothing is linked, and no story has Custom.ShippedRelease
  set. Everything interesting - links, ShippedRelease stamps, state transitions - is
  generated LIVE by the release-tracking automation during a demo, not pre-baked here.

  This resets AZURE DEVOPS ONLY. The GitHub side of a demo (the release tag, the
  GitHub Release, leftover demo branches) is reset separately - see LAB-GUIDE.md
  section 8.2, and provision/11-ReleaseBaseline.ps1 -Force to re-point the baseline
  tag at the current tip of main.

  -Reset undoes a demo run:
    1. Removes every System.LinkTypes.Related (and any stray Hierarchy) link between
       Release work items and User Stories
    2. Clears Custom.ShippedRelease on all stories
    3. Sets every Release back to 'New' and clears its deploy metadata
    4. Restores User Story states via 04-WorkItems.ps1 -ResetStates (the single
       source of truth for seeded story state - not duplicated here)

  Idempotent by title; -Reset is idempotent and safe against an already-clean env.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),
    [switch]$Reset
)
. "$PSScriptRoot/Common.ps1"

# Titles MUST exactly match the Custom.TargetRelease values used by 04-WorkItems.ps1
# so drift comparisons are a plain string compare, no mapping table. Both release
# fields are plain text (see 01-Process.ps1), so nothing enforces that match —
# it's convention, and drift detection is what catches a typo.
#
# The version is load-bearing, not decoration: it is the key
# release automation resolves a Release work item by, and it must match
# the `version` in package.json for the release that is currently pending. It is
# also the tag name the completed release publishes, which in turn bounds the next
# release's commit range.
$Releases = @(
    @{ title = '1.0.0'; version = '1.0.0' },
    @{ title = '1.1.0'; version = '1.1.0' },
    @{ title = '1.2.0'; version = '1.2.0' }
)

function Get-ExistingReleases {
    $wiql = @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='Release'" }
    $res = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') $wiql
    $ids = @($res.workItems | ForEach-Object { $_.id })
    $map = @{}
    if ($ids.Count -gt 0) {
        $items = (Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($ids -join ',')&`$expand=all")).value
        foreach ($it in $items) { $map[$it.fields.'System.Title'] = $it }
    }
    return $map
}

function New-Release { param($Cfg)
    # ADO rejects a non-initial State on create for this custom WIT; set it in a
    # follow-up transition (same pattern as 04-WorkItems.ps1).
    $ops = @(
        @{ op = 'add'; path = '/fields/System.Title'; value = $Cfg.title }
        @{ op = 'add'; path = '/fields/Custom.ReleaseVersion'; value = $Cfg.version }
    )
    $wi = Invoke-Ado POST (Get-ProjUrl 'wit/workitems/$Release') (ConvertTo-JsonArray $ops) 'application/json-patch+json'
    if ($wi.fields.'System.State' -ne 'New') {
        $wi = Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$($wi.id)") (ConvertTo-JsonArray @(@{ op = 'add'; path = '/fields/System.State'; value = 'New' })) 'application/json-patch+json'
    }
    Write-Host "  + [Release] $($Cfg.title) (#$($wi.id)) version=$($Cfg.version)"
    return $wi
}

function Set-ReleaseBaselineFields { param([int]$Id, $Cfg, $Existing)
    $ops = @()
    if ($Existing.fields.'Custom.ReleaseVersion' -ne $Cfg.version) { $ops += @{ op = 'add'; path = '/fields/Custom.ReleaseVersion'; value = $Cfg.version } }
    if ($ops.Count -gt 0) {
        Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$Id") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
        Write-Host "  ~ updated version on: $($Cfg.title)"
    }
}

# ---- Reset helpers ---------------------------------------------------------

function Get-AllStoriesWithFieldsAndRelations {
    $wiql = @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='User Story'" }
    $res = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') $wiql
    $ids = @($res.workItems | ForEach-Object { $_.id })
    $items = @()
    for ($i = 0; $i -lt $ids.Count; $i += 200) {
        $batch = $ids[$i..([Math]::Min($i + 199, $ids.Count - 1))]
        if (-not $batch) { continue }
        $items += (Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($batch -join ',')&`$expand=all")).value
    }
    return $items
}

# Remove every Release<->Story link (Related, and any stray Hierarchy). Relation
# removal is by index - read relations, compute indices to remove, then remove in
# DESCENDING order so an earlier removal doesn't shift the index of a later one.
function Remove-ReleaseLinks { param($ReleaseIds)
    $releaseUrls = @{}
    foreach ($id in $ReleaseIds) { $releaseUrls[(Invoke-Ado GET (Get-ProjUrl "wit/workitems/$id")).url] = $true }

    $removed = 0
    $stories = Get-AllStoriesWithFieldsAndRelations
    foreach ($story in $stories) {
        if (-not $story.relations) { continue }
        $toRemove = @()
        for ($i = 0; $i -lt $story.relations.Count; $i++) {
            $rel = $story.relations[$i]
            $isReleaseLink = ($rel.rel -eq 'System.LinkTypes.Related' -or $rel.rel -like 'System.LinkTypes.Hierarchy*') -and $releaseUrls.ContainsKey($rel.url)
            if ($isReleaseLink) { $toRemove += $i }
        }
        foreach ($idx in ($toRemove | Sort-Object -Descending)) {
            $ops = @(@{ op = 'remove'; path = "/relations/$idx" })
            Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$($story.id)") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
            $removed++
        }
    }
    Write-Host "  removed $removed release<->story link(s)"
}

function Clear-ShippedRelease {
    $cleared = 0
    $stories = Get-AllStoriesWithFieldsAndRelations
    foreach ($story in $stories) {
        if ($story.fields.'Custom.ShippedRelease') {
            $ops = @(@{ op = 'add'; path = '/fields/Custom.ShippedRelease'; value = '' })
            Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$($story.id)") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
            $cleared++
        }
    }
    Write-Host "  cleared Custom.ShippedRelease on $cleared stor$(if ($cleared -eq 1) { 'y' } else { 'ies' })"
}

function Reset-ReleaseWorkItems { param($Existing)
    foreach ($cfg in $Releases) {
        $wi = $Existing[$cfg.title]
        if (-not $wi) { continue }
        $ops = @(
            @{ op = 'add'; path = '/fields/System.State'; value = 'New' }
            @{ op = 'remove'; path = '/fields/Custom.DeployedOn' }
            @{ op = 'remove'; path = '/fields/Custom.DeployedBy' }
            @{ op = 'remove'; path = '/fields/Custom.ReleaseNotesUrl' }
        )
        try { Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$($wi.id)") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null }
        catch {
            # 'remove' on a field that was never set throws; retry with just the state change.
            Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$($wi.id)") (ConvertTo-JsonArray @(@{ op = 'add'; path = '/fields/System.State'; value = 'New' })) 'application/json-patch+json' | Out-Null
        }
        Write-Host "  reset: $($cfg.title) -> New (deploy metadata cleared)"
    }
}

# ---- Main -------------------------------------------------------------------

$existing = Get-ExistingReleases

if ($Reset) {
    Write-Host 'Resetting release-tracking baseline...'
    $releaseIds = $existing.Values | ForEach-Object { $_.id }
    Remove-ReleaseLinks $releaseIds
    Clear-ShippedRelease
    Reset-ReleaseWorkItems $existing
    Write-Host 'Restoring seeded story states via 04-WorkItems.ps1 -ResetStates...'
    & "$PSScriptRoot/04-WorkItems.ps1" -OrgName $OrgName -Project $Project -ResetStates
    Write-Host 'Reset complete. Baseline restored.'
    return
}

Write-Host 'Releases:'
foreach ($cfg in $Releases) {
    if ($existing.ContainsKey($cfg.title)) {
        Write-Host "  exists: [Release] $($cfg.title) (#$($existing[$cfg.title].id))"
        Set-ReleaseBaselineFields $existing[$cfg.title].id $cfg $existing[$cfg.title]
    } else {
        New-Release $cfg | Out-Null
    }
}
Write-Host 'Done. Baseline: 3 Release work items in New, no links, no Shipped Release values.'
