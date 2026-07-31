<#
  06-Layout.ps1 — Put the release-tracking custom fields (Target Release, Shipped
  Release) on the User Story form, in a 'Delivery' group. Idempotent.

  Per-control, not all-or-nothing: earlier versions of this script bailed out early
  if ANY target control was already present anywhere on the form, which meant a
  control added by a later run (e.g. Shipped Release, added after Target Release)
  would silently never get added on an environment that already had the others.
  This version computes the set of MISSING controls and adds only those.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' })
)
. "$PSScriptRoot/Common.ps1"

$Controls = @(
    @{ id = 'Custom.TargetRelease';  label = 'Target Release' },
    @{ id = 'Custom.ShippedRelease'; label = 'Shipped Release' }
)
$GroupLabel = 'Delivery'

function Find-ProcessId {
    $p = (Invoke-Ado GET (Get-CoreUrl 'work/processes')).value | Where-Object { $_.name -eq 'Contoso Agile' } | Select-Object -First 1
    if (-not $p) { throw "Process 'Contoso Agile' not found — run 01-Process.ps1 first." }
    return $p.typeId
}

function Find-UserStoryRef { param([string]$ProcId)
    $us = (Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workitemtypes")).value |
        Where-Object { $_.name -eq 'User Story' -and $_.customization -eq 'inherited' } | Select-Object -First 1
    if (-not $us) { throw 'Inherited User Story WIT not found — run 01-Process.ps1 first.' }
    return $us.referenceName
}

$procId = Find-ProcessId
$wit    = Find-UserStoryRef $procId
$layout = Invoke-Ado GET (Get-CoreUrl "work/processes/$procId/workItemTypes/$wit/layout")

# Find which target controls are already on the form, and which Delivery group (if
# any) already exists, so we can add ONLY what's missing.
$targets  = $Controls | ForEach-Object { $_.id }
$present  = @{}
$deliveryGroup = $null
foreach ($page in $layout.pages) {
    foreach ($sec in $page.sections) {
        foreach ($grp in $sec.groups) {
            if ($grp.label -eq $GroupLabel) { $deliveryGroup = $grp }
            foreach ($ctl in $grp.controls) { if ($targets -contains $ctl.id) { $present[$ctl.id] = $true } }
        }
    }
}
$missing = $Controls | Where-Object { -not $present.ContainsKey($_.id) }

if (-not $missing) { Write-Host 'All Delivery fields already on the form.'; Write-Host 'Done.'; return }

if ($deliveryGroup) {
    foreach ($c in $missing) {
        $body = @{ id = $c.id; label = $c.label; controlType = 'FieldControl'; visible = $true }
        Invoke-Ado POST (Get-CoreUrl "work/processes/$procId/workItemTypes/$wit/layout/groups/$($deliveryGroup.id)/controls") $body | Out-Null
        Write-Host "  + control '$($c.label)' added to existing 'Delivery' group"
    }
} else {
    $details = $layout.pages | Where-Object { $_.label -eq 'Details' } | Select-Object -First 1
    if (-not $details) { $details = $layout.pages[0] }
    $section = $details.sections[0]
    $body = @{
        label = $GroupLabel
        controls = $missing | ForEach-Object { @{ id = $_.id; label = $_.label; controlType = 'FieldControl'; visible = $true } }
    }
    Invoke-Ado POST (Get-CoreUrl "work/processes/$procId/workItemTypes/$wit/layout/pages/$($details.id)/sections/$($section.id)/groups") $body | Out-Null
    Write-Host "  + form group '$GroupLabel' with $($missing.Count) control(s): $(($missing | ForEach-Object { $_.label }) -join ', ')"
}
Write-Host 'Done.'
