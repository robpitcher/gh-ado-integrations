<#
  05-Views.ps1 — Project-scoped shared queries + the 'Contoso Delivery' dashboard
  (tiles + pie charts). Uses stock Agile fields plus the release-tracking custom
  fields (Custom.TargetRelease, Custom.ShippedRelease) added in 01-Process.ps1.
  The dashboard is recreated each run so it self-heals.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' })
)
. "$PSScriptRoot/Common.ps1"

$Prefix = 'SELECT [System.Id],[System.Title],[System.State],[System.AssignedTo],[System.AreaPath],[System.IterationPath],[Custom.TargetRelease],[Custom.ShippedRelease] FROM workitems '
$Scope  = "WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='User Story'"
# Release Register needs a different scope (System.WorkItemType='Release') — factor
# the project-team filter out rather than assuming every query shares $Scope.
$ProjectFilter = "[System.TeamProject]='$($script:Project)'"

$Queries = [ordered]@{
    'All Stories'       = $Prefix + $Scope + ' ORDER BY [System.State]'
    'App Team Stories'  = $Prefix + $Scope + " AND [System.AreaPath] UNDER '$($script:Project)\App' ORDER BY [System.State]"
    'QA Team Stories'   = $Prefix + $Scope + " AND [System.AreaPath] UNDER '$($script:Project)\QA' ORDER BY [System.State]"
    'DevOps Stories'    = $Prefix + $Scope + " AND [System.AreaPath] UNDER '$($script:Project)\DevOps' ORDER BY [System.State]"
    'Active Stories'    = $Prefix + $Scope + " AND [System.State]='Active' ORDER BY [System.AreaPath]"
    'Ready for Release Stories' = $Prefix + $Scope + " AND [System.State]='Ready for Release' ORDER BY [System.AreaPath]"

    # ---- Release tracking ---------------------------------------------------
    # NOTE: WIQL cannot compare two fields to each other — there is no way to
    # express [Custom.TargetRelease] <> [Custom.ShippedRelease] directly. Drift
    # queries are therefore written PER RELEASE, pinning one side to a literal.
    # The cross-release drift view lives in the CI job summary (see
    # ado-release-sync.yml), not in WIQL — don't try to
    # generalise this into one query.
    'Release Contents - 1.0.0'         = $Prefix + $Scope + " AND [Custom.ShippedRelease] = '1.0.0' ORDER BY [System.State]"
    'Release Contents - 1.1.0'         = $Prefix + $Scope + " AND [Custom.ShippedRelease] = '1.1.0' ORDER BY [System.State]"
    'Release Contents - 1.2.0'         = $Prefix + $Scope + " AND [Custom.ShippedRelease] = '1.2.0' ORDER BY [System.State]"

    # Planned for 1.0.0 but shipped elsewhere. Excludes empty ShippedRelease — a story
    # that simply hasn't shipped yet is not drift, it's just pending.
    'Release Drift - 1.0.0'            = $Prefix + $Scope + " AND [Custom.TargetRelease] = '1.0.0' AND [Custom.ShippedRelease] <> '1.0.0' AND [Custom.ShippedRelease] <> '' ORDER BY [System.State]"
    'Release Drift - 1.1.0'            = $Prefix + $Scope + " AND [Custom.TargetRelease] = '1.1.0' AND [Custom.ShippedRelease] <> '1.1.0' AND [Custom.ShippedRelease] <> '' ORDER BY [System.State]"
    'Release Drift - 1.2.0'            = $Prefix + $Scope + " AND [Custom.TargetRelease] = '1.2.0' AND [Custom.ShippedRelease] <> '1.2.0' AND [Custom.ShippedRelease] <> '' ORDER BY [System.State]"

    'Targeted 1.0.0 - Not Yet Shipped' = $Prefix + $Scope + " AND [Custom.TargetRelease] = '1.0.0' AND [Custom.ShippedRelease] = '' ORDER BY [System.State]"
    'Targeted 1.1.0 - Not Yet Shipped' = $Prefix + $Scope + " AND [Custom.TargetRelease] = '1.1.0' AND [Custom.ShippedRelease] = '' ORDER BY [System.State]"
    'Targeted 1.2.0 - Not Yet Shipped' = $Prefix + $Scope + " AND [Custom.TargetRelease] = '1.2.0' AND [Custom.ShippedRelease] = '' ORDER BY [System.State]"

    # Post-deploy cleanup that never happened — the demo's scoreboard tile.
    'Shipped but Not Closed'          = $Prefix + $Scope + " AND [Custom.ShippedRelease] <> '' AND [System.State] <> 'Closed' ORDER BY [System.State]"

    'Release Register' = "SELECT [System.Id],[System.Title],[System.State],[Custom.ReleaseVersion],[Custom.DeployedOn] FROM workitems WHERE $ProjectFilter AND [System.WorkItemType]='Release' ORDER BY [System.Title]"
}

function Ensure-Query { param([string]$Name, [string]$Wiql)
    $root = Invoke-Ado GET (Get-ProjUrl 'wit/queries/Shared%20Queries?$depth=2&$expand=all')
    $c = $root.children | Where-Object { $_.name -eq $Name -and -not $_.isFolder } | Select-Object -First 1
    if ($c) {
        $norm = { param($s) ($s -replace '\s+', '').ToLower() }
        if ((& $norm $c.wiql) -ne (& $norm $Wiql)) {
            Invoke-Ado PATCH (Get-ProjUrl "wit/queries/$($c.id)") @{ wiql = $Wiql } | Out-Null
            Write-Host "  ~ query updated: $Name"
        }
        return $c.id
    }
    $q = Invoke-Ado POST (Get-ProjUrl 'wit/queries/Shared%20Queries') @{ name = $Name; wiql = $Wiql; isFolder = $false }
    Write-Host "  + query: $Name"
    return $q.id
}

function Get-DefaultTeamId { (Invoke-Ado GET (Get-CoreUrl "projects/$(Get-ProjectId)")).defaultTeam.id }
function Get-DashUrl { param([string]$TeamId, [string]$Path = '')
    $proj = [uri]::EscapeDataString($script:Project)
    "$script:OrgUrl/$proj/$TeamId/_apis/dashboard/dashboards$Path" + '?api-version=7.1-preview.3'
}

function New-ScalarWidget { param([string]$Name, [string]$QueryId, [int]$Col, [int]$Row)
    @{
        name = $Name; position = @{ column = $Col; row = $Row }; size = @{ columnSpan = 1; rowSpan = 1 }
        contributionId = 'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget'
        settings = (@{ groupKey = 'completed'; queryId = $QueryId; colorRules = @() } | ConvertTo-Json -Compress)
    }
}

function New-ChartWidget { param([string]$Name, [string]$QueryId, [string]$GroupField, [int]$Col, [int]$Row)
    # Schema captured from a working UI-created pie chart: measure is an OBJECT
    # {aggregation,propertyName}; chartType 'PieChart'; scope 'WorkitemTracking.Queries'.
    # Reused exactly as-is (don't refactor) — this settings shape is fragile.
    $settings = @{
        scope = 'WorkitemTracking.Queries'; groupKey = $QueryId; title = $Name; chartType = 'PieChart'
        transformOptions = @{
            filter = $QueryId; groupBy = $GroupField
            orderBy = @{ direction = 'descending'; propertyName = 'value' }
            measure = @{ aggregation = 'count'; propertyName = '' }
            historyRange = $null; groupByTags = $false
        }
        userColors = @(); lastArtifactName = $Name
    } | ConvertTo-Json -Depth 10 -Compress
    @{
        name = $Name; position = @{ column = $Col; row = $Row }; size = @{ columnSpan = 2; rowSpan = 2 }
        contributionId = 'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.WitChartWidget'
        settings = $settings
    }
}

Write-Host 'Queries:'
$qids = @{}
foreach ($name in $Queries.Keys) { $qids[$name] = Ensure-Query $name $Queries[$name] }

Write-Host 'Dashboard:'
$teamId = Get-DefaultTeamId
$existing = (Invoke-Ado GET (Get-DashUrl $teamId)).value
foreach ($d in $existing) {
    if ($d.name -eq 'Contoso Delivery') {
        Invoke-Ado DELETE (Get-DashUrl $teamId "/$($d.id)") | Out-Null
        Write-Host "  removed existing 'Contoso Delivery' (will recreate)"
    }
}
$all = $qids['All Stories']
$widgets = @(
    (New-ScalarWidget 'Total Stories'   $all                        1 1),
    (New-ScalarWidget 'Active Stories'  $qids['Active Stories']     2 1),
    (New-ScalarWidget 'DevOps Stories'  $qids['DevOps Stories']     3 1),
    # Release-tracking scoreboard: the tile that should read zero once the
    # membership-sync and release-completion automation are wired up.
    (New-ScalarWidget 'Shipped but Not Closed' $qids['Shipped but Not Closed']       4 1),
    (New-ChartWidget  'Stories by State'  $all 'System.State'        1 2),
    (New-ChartWidget  'Stories by Area'   $all 'System.AreaPath'     3 2),
    (New-ChartWidget  'Stories by Sprint' $all 'System.IterationPath' 1 4),
    (New-ChartWidget  'Stories by Shipped Release' $all 'Custom.ShippedRelease'       3 4),
    (New-ScalarWidget 'Unshipped - Targeted 1.0.0' $qids['Targeted 1.0.0 - Not Yet Shipped'] 1 6)
)
Invoke-Ado POST (Get-DashUrl $teamId) @{ name = 'Contoso Delivery'; description = 'Demo delivery dashboard'; widgets = $widgets } | Out-Null
Write-Host "  + dashboard: Contoso Delivery ($(@($widgets | Where-Object { $_.contributionId -match 'Scalar' }).Count) tiles + $(@($widgets | Where-Object { $_.contributionId -match 'Chart' }).Count) charts)"
Write-Host 'Done.'
