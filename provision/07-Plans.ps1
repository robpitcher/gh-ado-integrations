<#
  07-Plans.ps1 — Delivery Plan 'Contoso Roadmap' showing User Stories from the
  App, QA, and DevOps teams across sprints, so cross-sprint dependency lines are
  visible. Recreated each run so the backlog level stays correct.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' })
)
. "$PSScriptRoot/Common.ps1"

$PlanName = 'Contoso Roadmap'

$existing = (Invoke-Ado GET (Get-ProjUrl 'work/plans')).value | Where-Object { $_.name -eq $PlanName } | Select-Object -First 1
if ($existing) {
    Invoke-Ado DELETE (Get-ProjUrl "work/plans/$($existing.id)") | Out-Null
    Write-Host "  removed existing '$PlanName' (will recreate)"
}

$projId = Get-ProjectId
$teams = @{}
foreach ($t in (Invoke-Ado GET (Get-CoreUrl "projects/$projId/teams")).value) { $teams[$t.name] = $t.id }

# Requirement category = User Story level, so stories show on their sprints and
# cross-sprint dependency lines render.
$mapping = @(
    @{ projectId = $projId; teamId = $teams['App Team'];    categoryReferenceName = 'Microsoft.RequirementCategory' },
    @{ projectId = $projId; teamId = $teams['QA Team'];     categoryReferenceName = 'Microsoft.RequirementCategory' },
    @{ projectId = $projId; teamId = $teams['DevOps Team']; categoryReferenceName = 'Microsoft.RequirementCategory' }
)
$body = @{
    name = $PlanName
    description = 'Cross-team roadmap (App + QA + DevOps) — stories across sprints with dependencies'
    type = 'deliveryTimelineView'
    properties = @{
        teamBacklogMappings = $mapping
        criteria = @()
        cardSettings = @{ fields = @{ showId = $true; showAssignedTo = $true; showState = $true; showTags = $true; showEmptyFields = $true; additionalFields = @() } }
        styleSettings = @()
        markers = @()
        tagStyles = @()
    }
}
$p = Invoke-Ado POST (Get-ProjUrl 'work/plans') $body
Write-Host "  + delivery plan: $PlanName ($($p.id))"
Write-Host 'Done.'
