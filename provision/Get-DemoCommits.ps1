<#
  Get-DemoCommits.ps1 - Print ready-to-paste git commands that create one trivial
  commit per User Story targeted at a given release, each with a
  Ready for Release AB#<id> transition in the message.

  Why this exists: the release membership sync (.github/workflows/ado-release-sync.yml)
  only links work items it can find, and it finds them by reading AB#<id> out of
  commit messages in the range since the last release tag. The state name also asks
  the native Azure Boards integration to move the story into the Resolved category.
  Work item IDs are assigned by ADO at provisioning time and differ per environment,
  so they can't be hardcoded in LAB-GUIDE.md - this script generates the right
  commands for YOUR environment.

  This does not create a branch or commit anything itself - it only prints the
  commands, so you can review/edit before running them.

  Example:
    ./Get-DemoCommits.ps1 -OrgName myorg -Release '1.0.0'
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),
    [Parameter(Mandatory)][string]$Release   # must exactly match a Custom.TargetRelease value, e.g. '1.0.0'
)
. "$PSScriptRoot/Common.ps1"

$safeRelease = $Release -replace "'", "''"
$wiql = @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)' AND [System.WorkItemType]='User Story' AND [Custom.TargetRelease]='$safeRelease' ORDER BY [System.Id]" }
$res = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') $wiql
$ids = @($res.workItems | ForEach-Object { $_.id })

if ($ids.Count -eq 0) {
    Write-Warning "No User Stories found with Custom.TargetRelease = '$Release'. Nothing to generate."
    return
}

$items = (Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($ids -join ',')")).value

Write-Host "# Demo commits for release '$Release' ($($items.Count) stor$(if ($items.Count -eq 1) { 'y' } else { 'ies' }))"
Write-Host "# Paste these on main, AFTER the baseline tag exists:"
Write-Host "#   ./11-ReleaseBaseline.ps1 -GitHubRepo <owner>/contoso-logistics"
Write-Host ''

foreach ($it in $items) {
    $id = $it.fields.'System.Id'
    $title = $it.fields.'System.Title'
    $safeTitle = ($title -replace '"', '\"')
    Write-Host "git commit --allow-empty -m `"chore: touch up $safeTitle - Ready for Release AB#$id`""
}

Write-Host ''
Write-Host "git push"
