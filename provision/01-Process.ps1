<#
  01-Process.ps1 — Create the 'Contoso Agile' inherited process (a clean copy of
  the built-in Agile process) and layer the release-tracking customizations on top:

    - Custom.TargetRelease plain-text field on User Story (product-owner intent).
      This was a prerequisite the release-tracking series assumed already existed;
      it doesn't in this environment's history, so it is reintroduced here rather
      than in a separate issue. Plain text, not a picklist: Azure DevOps can't
      convert a field between the two in place, so a picklist turns every new
      release name into a process migration.
    - Custom.ShippedRelease plain-text field on User Story (automation-only actual).
    - Ready for Release state on User Story, in the built-in Resolved category.
    - A brand-new custom 'Release' work item type — NOT derived from any system
      type — with its own states and deploy-metadata fields.

  All customizations are additive and idempotent; re-running is a no-op.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' })
)
. "$PSScriptRoot/Common.ps1"

$AgileTypeId = 'adcc42ab-9882-485e-a3ed-7678f01f66bc'
$ProcessName = 'Contoso Agile'

# Release WIT: states and deploy-metadata fields. Kept module-level so Verify.ps1's
# expectations and this script's creation logic can never drift apart.
#
# There is deliberately no 'Release Branch' field. Releases are bounded by tags on
# main, not by a release/** branch, so Custom.ReleaseVersion is the key that
# release automation resolves a Release work item by. An org provisioned
# before that change keeps a stray Custom.ReleaseBranch field; removing a field
# from an inherited process is destructive, so it is simply left unused.
$script:ReleaseStates = @(
    @{ name = 'New';    stateCategory = 'Proposed';   color = 'b2b2b2' },
    @{ name = 'Active'; stateCategory = 'InProgress'; color = '007acc' },
    @{ name = 'Closed'; stateCategory = 'Completed';  color = '339947' }
)
$script:UserStoryStates = @(
    @{ name = 'Ready for Release'; stateCategory = 'Resolved'; color = 'f2cb1d' }
)
$script:ReleaseTextFields = @(
    @{ name = 'Release Version';    ref = 'Custom.ReleaseVersion';    type = 'string' },
    @{ name = 'Deployed On';        ref = 'Custom.DeployedOn';        type = 'dateTime' },
    @{ name = 'Deployed By';        ref = 'Custom.DeployedBy';        type = 'string' },
    @{ name = 'Release Notes URL';  ref = 'Custom.ReleaseNotesUrl';   type = 'string' }
)
$script:TargetRelease   = @{ name = 'Target Release'; ref = 'Custom.TargetRelease'; type = 'string' }
$script:ShippedRelease  = @{ name = 'Shipped Release'; ref = 'Custom.ShippedRelease'; type = 'string' }

function Get-OrCreateProcess {
    $procs = (Invoke-Ado GET (Get-CoreUrl 'work/processes')).value
    $existing = $procs | Where-Object { $_.name -eq $ProcessName } | Select-Object -First 1
    if ($existing) { Write-Host "Process exists: $ProcessName ($($existing.typeId))"; return $existing.typeId }
    $body = @{ parentProcessTypeId = $AgileTypeId; name = $ProcessName; description = 'Contoso Logistics demo process (clean Agile copy — customize as needed)' }
    $p = Invoke-Ado POST (Get-CoreUrl 'work/processes') $body
    Write-Host "Created process: $ProcessName ($($p.typeId))"
    return $p.typeId
}

# System work item types must be *derived* (inheritsFrom the system type) before
# adding custom states/fields/rules to them. A brand-new custom type (like Release,
# below) must NOT be derived — omitting inheritsFrom is what makes it genuinely new.
function Get-UserStoryWit {
    param([string]$ProcId)
    $wits = (Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workitemtypes")).value
    $us = $wits | Where-Object { $_.name -eq 'User Story' } | Select-Object -First 1
    if ($us.customization -eq 'inherited') { Write-Host "User Story already derived: $($us.referenceName)"; return $us.referenceName }
    $body = @{ name = $us.name; color = $us.color; icon = $us.icon; description = $us.description; inheritsFrom = $us.referenceName; isDisabled = $false }
    $w = Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workitemtypes") $body
    Write-Host "Derived User Story: $($w.referenceName)"
    return $w.referenceName
}

# Generic states helper: GET current states, add only what's missing (idempotent).
# `order` is deliberately omitted on every state — ADO auto-places states and
# explicit values collide with the built-in ones.
function Add-States {
    param([string]$ProcId, [string]$Wit, [array]$States)
    $have = (Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/states")).value | ForEach-Object { $_.name }
    foreach ($s in $States) {
        if ($have -contains $s.name) { Write-Host "  state exists: $($s.name)"; continue }
        Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/states") $s | Out-Null
        Write-Host "  + state: $($s.name) ($($s.stateCategory))"
    }
}

# Guard so re-runs don't fail trying to (re)create an org-level field that already exists.
function Test-OrgField { param([string]$Ref)
    try { Invoke-Ado GET (Get-CoreUrl "wit/fields/$Ref") | Out-Null; return $true } catch { return $false }
}

# Both release fields are plain text. `Custom.ShippedRelease` is written only by
# automation, so there's no list to maintain and no validation failure the first
# time a new release name appears. `Custom.TargetRelease` is plain text for the
# same practical reason: a picklist has to be edited in the process every time a
# release is added, and Azure DevOps will not convert a field between picklist and
# text in place — so the list becomes a migration problem the moment it's wrong.
#
# The trade-off is real and worth stating: nothing now validates that a story's
# Target Release matches a Release work item's title. That match is convention
# (see 09-Releases.ps1) and drift detection is what catches a typo, rather than
# the field refusing it up front.
function Add-TextField {
    param([string]$ProcId, [string]$Wit, [string]$Name, [string]$Ref, [string]$Type = 'string')
    $have = (Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/fields")).value
    if ($have | Where-Object { $_.name -eq $Name }) { Write-Host "  field exists: $Name"; return }
    if (-not (Test-OrgField $Ref)) {
        Invoke-Ado POST (Get-CoreUrl 'wit/fields') @{ name = $Name; referenceName = $Ref; type = $Type; usage = 'workItem' } | Out-Null
    }
    Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/fields") @{ referenceName = $Ref; required = $false } | Out-Null
    Write-Host "  + text field: $Name ($Ref, $Type)"
}

# Place Custom.ReleaseVersion on the Release WIT form inside a 'Release Info' group.
# Idempotent: checks both for the control (anywhere on form) and the group before POSTing.
function Add-ReleaseFormLayout {
    param([string]$ProcId, [string]$Wit)
    $layout = Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/layout")
    $releaseInfoGroup = $null
    $alreadyOnForm = $false
    foreach ($page in $layout.pages) {
        foreach ($sec in $page.sections) {
            foreach ($grp in $sec.groups) {
                if ($grp.label -eq 'Release Info') { $releaseInfoGroup = $grp }
                foreach ($ctl in $grp.controls) { if ($ctl.id -eq 'Custom.ReleaseVersion') { $alreadyOnForm = $true } }
            }
        }
    }
    if ($alreadyOnForm) { Write-Host "  Release Version control already on Release form"; return }

    $control = @{ id = 'Custom.ReleaseVersion'; label = 'Release Version'; controlType = 'FieldControl'; visible = $true }
    if ($releaseInfoGroup) {
        Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/layout/groups/$($releaseInfoGroup.id)/controls") $control | Out-Null
        Write-Host "  + Release Version control added to existing 'Release Info' group"
    } else {
        $details = $layout.pages | Where-Object { $_.label -eq 'Details' } | Select-Object -First 1
        if (-not $details) { $details = $layout.pages[0] }
        $section = $details.sections[0]
        $body = @{ label = 'Release Info'; controls = @($control) }
        Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/layout/pages/$($details.id)/sections/$($section.id)/groups") $body | Out-Null
        Write-Host "  + form group 'Release Info' with Release Version control added to Release WIT"
    }
}

# Add a process rule that makes Custom.ReleaseVersion required on every save of a
# Release work item. ADO process rules use makeRequired to block saves when the field
# is blank. The 'isEnabled' condition type with value '' means the rule always fires.
function Add-ReleaseVersionRule {
    param([string]$ProcId, [string]$Wit)
    $rules = (Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/rules")).value
    $exists = $rules | Where-Object {
        $_.actions | Where-Object { $_.actionType -eq 'makeRequired' -and $_.targetField -eq 'Custom.ReleaseVersion' }
    } | Select-Object -First 1
    if ($exists) { Write-Host "  Release Version required rule already exists"; return }
    $body = @{
        name       = 'Release Version is required'
        conditions = @(@{ conditionType = 'isEnabled'; field = ''; value = '' })
        actions    = @(@{ actionType = 'makeRequired'; targetField = 'Custom.ReleaseVersion'; value = '' })
        isDisabled = $false
    }
    Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workItemTypes/$Wit/rules") $body | Out-Null
    Write-Host "  + process rule: Release Version is required"
}

# Create a brand-new custom work item type — deliberately NOT derived (no
# inheritsFrom) so it is a genuinely new type rather than a derived system type.
function Get-OrCreateReleaseWit {
    param([string]$ProcId)
    $wits = (Invoke-Ado GET (Get-CoreUrl "work/processes/$ProcId/workitemtypes")).value
    $existing = $wits | Where-Object { $_.name -eq 'Release' } | Select-Object -First 1
    if ($existing) { Write-Host "WIT exists: Release ($($existing.referenceName))"; return $existing.referenceName }
    $body = @{ name = 'Release'; description = 'A release: state, version, and deploy metadata. Contents are derived from the commits between release tags on main.'; color = '773b93'; icon = 'icon_airplane'; isDisabled = $false }
    $w = Invoke-Ado POST (Get-CoreUrl "work/processes/$ProcId/workitemtypes") $body
    Write-Host "Created WIT: Release ($($w.referenceName))"
    return $w.referenceName
}

$procId  = Get-OrCreateProcess
$usWit   = Get-UserStoryWit $procId
Write-Host "User Story WIT: $usWit"

Add-States $procId $usWit $script:UserStoryStates
Add-TextField $procId $usWit $script:TargetRelease.name $script:TargetRelease.ref $script:TargetRelease.type
Add-TextField $procId $usWit $script:ShippedRelease.name $script:ShippedRelease.ref $script:ShippedRelease.type

$releaseWit = Get-OrCreateReleaseWit $procId
Write-Host "Release WIT: $releaseWit"
Add-States $procId $releaseWit $script:ReleaseStates
foreach ($f in $script:ReleaseTextFields) { Add-TextField $procId $releaseWit $f.name $f.ref $f.type }
Add-ReleaseFormLayout $procId $releaseWit
Add-ReleaseVersionRule $procId $releaseWit

# IMPORTANT — do not add 'Release' to any backlog level (portfolio backlog).
# Doing so would let work items be *parented* to a Release. A work item can only
# have one parent, and stories here already parent to Features — a Release parent
# link would either be rejected or silently compete with that hierarchy. The
# Release <-> User Story relationship must always be System.LinkTypes.Related
# (many-to-many, no hierarchy conflict). Surface Release via queries and a
# dashboard instead (see 05-Views.ps1) — never via a backlog/board.

Write-Host "PROCESS_ID=$procId"
Write-Host 'Done.'
