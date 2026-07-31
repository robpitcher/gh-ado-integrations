<#
  08-Pipeline.ps1 (OPTIONAL) — Create a GitHub service connection + an ADO pipeline
  that builds/tests a GitHub repo (npm ci + npm test via its azure-pipelines.yml).
  Requires the GitHub repo to contain azure-pipelines.yml on its default branch and
  a GitHub token from `gh auth token`. Idempotent.

  Example:
    ./08-Pipeline.ps1 -OrgName myorg -GitHubRepo myuser/contoso-logistics
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),
    [Parameter(Mandatory)][string]$GitHubRepo,   # e.g. 'owner/contoso-logistics'
    [string]$EndpointName = 'github-contoso',
    [string]$PipelineName = 'contoso-logistics-ci'
)
. "$PSScriptRoot/Common.ps1"

function Get-GhToken {
    $tok = (gh auth token 2>$null)
    if (-not $tok) { throw "Could not get a GitHub token via 'gh auth token'. Run 'gh auth login' first." }
    return $tok.Trim()
}

function Ensure-Endpoint {
    $eps = (Invoke-Ado GET (Get-ProjUrl 'serviceendpoint/endpoints' '7.1-preview.4')).value
    $e = $eps | Where-Object { $_.name -eq $EndpointName } | Select-Object -First 1
    if ($e) { Write-Host "  service connection exists: $EndpointName"; return $e.id }
    $projId = Get-ProjectId
    $body = @{
        name = $EndpointName; type = 'github'; url = 'https://github.com'
        authorization = @{ scheme = 'Token'; parameters = @{ accessToken = (Get-GhToken) } }
        isShared = $false; owner = 'library'
        serviceEndpointProjectReferences = @(@{ projectReference = @{ id = $projId; name = $script:Project }; name = $EndpointName })
    }
    $e = Invoke-Ado POST (Get-ProjUrl 'serviceendpoint/endpoints' '7.1-preview.4') $body
    Write-Host "  + service connection: $EndpointName ($($e.id))"
    return $e.id
}

function Ensure-Pipeline { param([string]$EndpointId)
    $pls = (Invoke-Ado GET (Get-ProjUrl 'pipelines' '7.1-preview.1')).value
    $p = $pls | Where-Object { $_.name -eq $PipelineName } | Select-Object -First 1
    if ($p) { Write-Host "  pipeline exists: $PipelineName (id $($p.id))"; return $p.id }
    $body = @{
        name = $PipelineName; folder = '\'
        configuration = @{
            type = 'yaml'; path = '/azure-pipelines.yml'
            repository = @{ fullName = $GitHubRepo; connection = @{ id = $EndpointId }; type = 'gitHub' }
        }
    }
    $p = Invoke-Ado POST (Get-ProjUrl 'pipelines' '7.1-preview.1') $body
    Write-Host "  + pipeline: $PipelineName (id $($p.id))"
    return $p.id
}

$eid = Ensure-Endpoint
Ensure-Pipeline $eid | Out-Null
Write-Host "Pipeline ready. Trigger it from ADO -> Pipelines -> $PipelineName, or push to $GitHubRepo."
Write-Host 'Done.'
