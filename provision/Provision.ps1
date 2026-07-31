<#
  Provision.ps1 — Run the full Contoso Logistics ADO provisioner end to end.

  Prereqs: PowerShell 7+, Azure CLI (`az login` to the account that owns the org),
  and the `azure-devops` CLI extension is NOT required (we call REST directly).
  `-IncludeGitHub` also needs `gh auth login`.

  Examples:
    ./Provision.ps1 -OrgName myorg
    ./Provision.ps1 -OrgName myorg -Project "Contoso Logistics" `
                    -IncludePipeline -GitHubRepo myuser/contoso-logistics
    ./Provision.ps1 -OrgName myorg -IncludeGitHub -GitHubRepo myuser/contoso-logistics

  -OrgName accepts either a bare org name ("myorg") or a full URL
  ("https://dev.azure.com/myorg").
#>
param(
    [Parameter(Mandatory)][Alias('Org','OrgUrl')][string]$OrgName,
    [string]$Project = 'Contoso Logistics',
    [switch]$Force,            # allow 02 to recreate a project that's on a different process
    [switch]$IncludePipeline,  # also run the optional GitHub (ADO) pipeline step
    [switch]$IncludeGitHub,    # also provision GitHub Environments (dev/stage/production) + the release baseline tag
    [string]$GitHubRepo        # required with -IncludePipeline or -IncludeGitHub (e.g. owner/contoso-logistics)
)
$ErrorActionPreference = 'Stop'

if ($IncludePipeline -and -not $GitHubRepo) { throw 'Pass -GitHubRepo owner/repo when using -IncludePipeline.' }
if ($IncludeGitHub -and -not $GitHubRepo) { throw 'Pass -GitHubRepo owner/repo when using -IncludeGitHub.' }

$steps = @('01-Process', '02-Project', '03-Structure', '04-WorkItems', '09-Releases', '05-Views', '06-Layout', '07-Plans')
foreach ($s in $steps) {
    Write-Host "`n========== $s =========="
    if ($s -eq '02-Project') { & "$PSScriptRoot/$s.ps1" -OrgName $OrgName -Project $Project -Force:$Force }
    else                     { & "$PSScriptRoot/$s.ps1" -OrgName $OrgName -Project $Project }
}

if ($IncludePipeline) {
    Write-Host "`n========== 08-Pipeline (optional) =========="
    & "$PSScriptRoot/08-Pipeline.ps1" -OrgName $OrgName -Project $Project -GitHubRepo $GitHubRepo
}

if ($IncludeGitHub) {
    Write-Host "`n========== 10-GitHubEnvironments (optional) =========="
    & "$PSScriptRoot/10-GitHubEnvironments.ps1" -GitHubRepo $GitHubRepo

    Write-Host "`n========== 11-ReleaseBaseline (optional) =========="
    & "$PSScriptRoot/11-ReleaseBaseline.ps1" -GitHubRepo $GitHubRepo
}

Write-Host "`nAll steps complete. Run ./Verify.ps1 -OrgName $OrgName to confirm."
