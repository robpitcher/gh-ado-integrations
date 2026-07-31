<#
  02-Project.ps1 — Ensure the project exists and uses the 'Contoso Agile' process
  (an inherited Agile process with the release-tracking fields, work item type,
  and Ready for Release User Story state added by 01-Process.ps1).
  - Missing            -> created on the Contoso Agile process.
  - On Contoso Agile   -> left as-is.
  - On another process -> only recreated when -Force is passed (DESTRUCTIVE: the
                          project is deleted and re-created, losing its data).
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),
    [switch]$Force
)
. "$PSScriptRoot/Common.ps1"

$ProcessName = 'Contoso Agile'

function Find-ProcessId {
    $p = (Invoke-Ado GET (Get-CoreUrl 'work/processes')).value | Where-Object { $_.name -eq $ProcessName } | Select-Object -First 1
    if (-not $p) { throw "Process '$ProcessName' not found — run 01-Process.ps1 first." }
    return $p.typeId
}

function Get-Project {
    (Invoke-Ado GET (Get-CoreUrl 'projects')).value | Where-Object { $_.name -eq $script:Project } | Select-Object -First 1
}

function Get-ProjectProcessId { param($ProjObj)
    $props = (Invoke-Ado GET (Get-CoreUrl "projects/$($ProjObj.id)/properties?keys=System.ProcessTemplateType" '7.1-preview.1')).value
    ($props | Where-Object { $_.name -eq 'System.ProcessTemplateType' }).value
}

function Wait-Operation { param([string]$OpUrl)
    for ($i = 0; $i -lt 60; $i++) {
        $sep = if ($OpUrl -match '\?') { '&' } else { '?' }
        $op = Invoke-Ado GET ("$OpUrl$sep" + 'api-version=7.1')
        if ($op.status -in @('succeeded','failed','cancelled')) { return $op.status }
        Start-Sleep -Seconds 3
    }
    return 'timeout'
}

function Remove-ProjectAndWait { param($ProjObj)
    $r = Invoke-Ado DELETE (Get-CoreUrl "projects/$($ProjObj.id)")
    if ($r.url) { Write-Host "  deleting... $(Wait-Operation $r.url)" }
    for ($i = 0; $i -lt 60; $i++) { if (-not (Get-Project)) { Write-Host '  project deleted'; return }; Start-Sleep -Seconds 3 }
}

function New-ProjectAndWait { param([string]$ProcId)
    $body = @{
        name = $script:Project
        description = 'Generic ADO demo environment - art of the possible'
        capabilities = @{
            versioncontrol  = @{ sourceControlType = 'Git' }
            processTemplate = @{ templateTypeId = $ProcId }
        }
    }
    $r = Invoke-Ado POST (Get-CoreUrl 'projects') $body
    if ($r.url) { Write-Host "  creating... $(Wait-Operation $r.url)" }
    for ($i = 0; $i -lt 60; $i++) {
        $p = Get-Project
        if ($p -and $p.state -eq 'wellFormed') { Write-Host "  project ready: $($p.id)"; return }
        Start-Sleep -Seconds 3
    }
    throw 'project did not reach wellFormed'
}

$target = Find-ProcessId
$proj   = Get-Project
if ($proj) {
    $current = Get-ProjectProcessId $proj
    if ($current -eq $target) { Write-Host "Project already on '$ProcessName' — nothing to do."; return }
    if (-not $Force) {
        throw "Project '$script:Project' exists but uses a different process ($current). Re-run with -Force to delete and recreate it on '$ProcessName' (DESTRUCTIVE), or choose a new project name."
    }
    Write-Host "Recreating project on '$ProcessName' (-Force)..."
    Remove-ProjectAndWait $proj
}
New-ProjectAndWait $target
Write-Host 'Done.'
