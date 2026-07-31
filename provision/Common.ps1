<#
  Common.ps1 — shared helpers for the Contoso Logistics ADO provisioner.

  Dot-source this from each step script AFTER its param() block sets $OrgName and
  $Project. Auth uses the Azure CLI AAD token (no PAT) — run `az login` first.

  $OrgName accepts either a bare org name ("myorg") or a full URL
  ("https://dev.azure.com/myorg"); a bare name is expanded to dev.azure.com.

  Requires PowerShell 7+.
#>

if (-not $OrgName)  { throw "Org not set. Pass -OrgName <your-org> (or a full URL https://dev.azure.com/<your-org>)." }
if (-not $Project)  { $Project = 'Contoso Logistics' }

# Accept either a bare org name ("myorg") or a full URL ("https://dev.azure.com/myorg").
$resolvedOrg = $OrgName.Trim().TrimEnd('/')
if ($resolvedOrg -notmatch '^https?://') { $resolvedOrg = "https://dev.azure.com/$resolvedOrg" }
$script:OrgUrl        = $resolvedOrg
$script:Project       = $Project
$script:AdoResource   = '499b84ac-1321-427f-aa17-267ca6975798'  # Azure DevOps app id
$script:AdoToken      = $null
$script:AdoTokenExp   = [datetime]::MinValue
$script:ProjectIdCache = $null

function Get-AdoToken {
    if ($script:AdoToken -and $script:AdoTokenExp -gt (Get-Date).AddMinutes(2)) { return $script:AdoToken }
    $raw = az account get-access-token --resource $script:AdoResource -o json 2>$null
    if (-not $raw) { throw "Could not get an Azure CLI token. Run 'az login' with the account that owns the ADO org." }
    $tok = $raw | ConvertFrom-Json
    $script:AdoToken    = $tok.accessToken
    $script:AdoTokenExp = (Get-Date).AddMinutes(50)
    return $script:AdoToken
}

function Invoke-Ado {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        $Body,
        [string]$ContentType = 'application/json'
    )
    $headers = @{ Authorization = "Bearer $(Get-AdoToken)" }
    $params  = @{ Method = $Method; Uri = $Url; Headers = $headers; ContentType = $ContentType }
    if ($null -ne $Body) {
        $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 }
    }
    $maxAttempts = 5
    for ($attempt = 1; ; $attempt++) {
        try {
            return Invoke-RestMethod @params
        }
        catch {
            $resp   = $_.Exception.Response
            $status = if ($resp) { [int]$resp.StatusCode } else { 0 }
            # Retry transient failures: connection-level errors (status 0), throttling (429), and 5xx.
            $transient = ($status -eq 0) -or ($status -in 429, 500, 502, 503, 504)
            if (-not $transient -or $attempt -ge $maxAttempts) {
                $detail = $_.ErrorDetails.Message
                throw "ADO $Method $Url failed: $($_.Exception.Message)`n$detail"
            }
            $delay = [math]::Min(30, [math]::Pow(2, $attempt))
            Write-Warning "ADO $Method $Url transient failure (attempt $attempt/$maxAttempts, status $status): $($_.Exception.Message). Retrying in $delay s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-CoreUrl {
    param([string]$Path, [string]$Api = '7.1')
    $sep = if ($Path -match '\?') { '&' } else { '?' }
    "$script:OrgUrl/_apis/$Path$sep" + "api-version=$Api"
}

function Get-ProjUrl {
    param([string]$Path, [string]$Api = '7.1')
    $sep  = if ($Path -match '\?') { '&' } else { '?' }
    $proj = [uri]::EscapeDataString($script:Project)
    "$script:OrgUrl/$proj/_apis/$Path$sep" + "api-version=$Api"
}

function Get-ProjectId {
    if ($script:ProjectIdCache) { return $script:ProjectIdCache }
    $projs = (Invoke-Ado GET (Get-CoreUrl 'projects')).value
    $p = $projs | Where-Object { $_.name -eq $script:Project } | Select-Object -First 1
    if (-not $p) { throw "Project '$script:Project' not found in org $script:OrgUrl." }
    $script:ProjectIdCache = $p.id
    return $p.id
}

# Serialize an array as a JSON array even when it has a single element (PS7).
# Note: -AsArray already guarantees array output; a leading comma here would
# wrap $Items in an extra array and emit a nested [[...]] (invalid JSON-Patch).
function ConvertTo-JsonArray { param($Items) $Items | ConvertTo-Json -Depth 30 -AsArray }
