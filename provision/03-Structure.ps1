<#
  03-Structure.ps1 — Teams (App/QA/DevOps), area paths, and 3 sprints (past/current/future),
  with area + iteration assignments per team. Idempotent. Also handles migration of a
  previously-provisioned environment: Dev Team -> App Team, 'Dev' area -> 'App'.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' })
)
. "$PSScriptRoot/Common.ps1"

# Teams and their corresponding area paths (in matching order).
$Teams = @('App Team', 'QA Team', 'DevOps Team')
$Areas = @('App', 'QA', 'DevOps')

function Get-TeamUrl { param([string]$TeamId, [string]$Path)
    $proj = [uri]::EscapeDataString($script:Project)
    "$script:OrgUrl/$proj/$TeamId/_apis/$Path" + '?api-version=7.1'
}

function Ensure-Team { param([string]$Name)
    $projId = Get-ProjectId
    $teams = (Invoke-Ado GET (Get-CoreUrl "projects/$projId/teams")).value
    $t = $teams | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($t) { return $t.id }

    # Migration: if a legacy name maps to this team, rename it instead of creating a new one.
    $legacyMap = @{ 'App Team' = 'Dev Team' }
    if ($legacyMap.ContainsKey($Name)) {
        $legacy = $teams | Where-Object { $_.name -eq $legacyMap[$Name] } | Select-Object -First 1
        if ($legacy) {
            Invoke-Ado PATCH (Get-CoreUrl "projects/$projId/teams/$($legacy.id)") @{ name = $Name } | Out-Null
            Write-Host "  ~ renamed team: $($legacyMap[$Name]) -> $Name"
            return $legacy.id
        }
    }

    $t = Invoke-Ado POST (Get-CoreUrl "projects/$projId/teams") @{ name = $Name; description = "$Name (demo)" }
    Write-Host "  + team: $Name"
    return $t.id
}

function Ensure-Area { param([string]$Name)
    $existing = Invoke-Ado GET (Get-ProjUrl 'wit/classificationnodes/areas?$depth=1')
    $kids = @($existing.children | ForEach-Object { $_.name })
    if ($kids -contains $Name) { return }

    # Migration: rename legacy area node if present.
    $legacyMap = @{ 'App' = 'Dev' }
    if ($legacyMap.ContainsKey($Name)) {
        $legacyNode = $existing.children | Where-Object { $_.name -eq $legacyMap[$Name] } | Select-Object -First 1
        if ($legacyNode) {
            $nodeId = $legacyNode.id
            Invoke-Ado PATCH (Get-ProjUrl "wit/classificationnodes/areas/$nodeId") @{ name = $Name } | Out-Null
            Write-Host "  ~ renamed area: $($legacyMap[$Name]) -> $Name"
            return
        }
    }

    Invoke-Ado POST (Get-ProjUrl 'wit/classificationnodes/areas') @{ name = $Name } | Out-Null
    Write-Host "  + area path: $Name"
}

function Ensure-Iteration { param([string]$Name, [string]$Start, [string]$Finish)
    $existing = Invoke-Ado GET (Get-ProjUrl 'wit/classificationnodes/iterations?$depth=1')
    $node = $existing.children | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($node) { return $node }
    $body = @{ name = $Name; attributes = @{ startDate = $Start; finishDate = $Finish } }
    $node = Invoke-Ado POST (Get-ProjUrl 'wit/classificationnodes/iterations') $body
    Write-Host "  + iteration: $Name ($($Start.Substring(0,10))..$($Finish.Substring(0,10)))"
    return $node
}

function Set-TeamArea { param([string]$TeamId, [string]$Area)
    $val = "$($script:Project)\$Area"
    $body = @{ defaultValue = $val; values = @(@{ value = $val; includeChildren = $false }) }
    Invoke-Ado PATCH (Get-TeamUrl $TeamId 'work/teamsettings/teamfieldvalues') $body | Out-Null
    Write-Host "    $($TeamId.Substring(0,8)) area -> $Area"
}

function Add-TeamIterations { param([string]$TeamId, $IterNodes, [string]$RootId)
    $settingsUrl = Get-TeamUrl $TeamId 'work/teamsettings'
    $cur = Invoke-Ado GET $settingsUrl
    if ($cur.backlogIteration.id -ne $RootId) { Invoke-Ado PATCH $settingsUrl @{ backlogIteration = $RootId } | Out-Null }
    $base = Get-TeamUrl $TeamId 'work/teamsettings/iterations'
    $have = @((Invoke-Ado GET $base).value | ForEach-Object { $_.id })
    foreach ($n in $IterNodes) {
        if ($have -contains $n.identifier) { continue }
        Invoke-Ado POST $base @{ id = $n.identifier } | Out-Null
    }
    Write-Host "    $($TeamId.Substring(0,8)) iterations assigned"
}

function Iso { param([datetime]$D) $D.ToString('yyyy-MM-ddT00:00:00Z') }

$today = (Get-Date).Date
$sprints = @(
    @{ name = 'Sprint 1'; start = $today.AddDays(-14); finish = $today.AddDays(-1) },
    @{ name = 'Sprint 2'; start = $today;              finish = $today.AddDays(13) },
    @{ name = 'Sprint 3'; start = $today.AddDays(14);  finish = $today.AddDays(27) }
)

Write-Host 'Teams:'
$teamIds = $Teams | ForEach-Object { Ensure-Team $_ }
Write-Host 'Area paths:'
$Areas | ForEach-Object { Ensure-Area $_ }
Write-Host 'Iterations:'
$root = Invoke-Ado GET (Get-ProjUrl 'wit/classificationnodes/iterations')
$rootId = $root.identifier
$iterNodes = $sprints | ForEach-Object { Ensure-Iteration $_.name (Iso $_.start) (Iso $_.finish) }
Write-Host 'Assign area + iterations to teams:'
for ($i = 0; $i -lt $teamIds.Count; $i++) {
    Set-TeamArea $teamIds[$i] $Areas[$i]
    Add-TeamIterations $teamIds[$i] $iterNodes $rootId
}
Write-Host 'Done.'
