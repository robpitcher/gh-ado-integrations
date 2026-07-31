<#
  04-WorkItems.ps1 — Seed 3 Epics (Order Tracking, Warehouse Automation, DevOps) with Features
  and User Stories
  across states, sprints, areas, and cross-sprint dependency links. Uses stock
  Agile states plus Ready for Release in the Resolved category. Idempotent by title.

  Logistics area uses App (app dev stories) and QA (quality/test stories).
  DevOps area contains platform, CI/CD, IaC, observability, and security stories.

  Every story also gets a Custom.TargetRelease value (product-owner intent, for the
  release-tracking scenario — see 09-Releases.ps1), derived deterministically from
  its sprint: Sprint 1 -> 1.0.0, Sprint 2 -> 1.1.0, Sprint 3 -> 1.2.0.

  -ResetStates force-PATCHes every seeded story back to its declared `state` value.
  This is the ONLY place that restores story state after a demo run — 09-Releases.ps1
  -Reset calls into it rather than duplicating the state table.
#>
param(
    [Alias('Org','OrgUrl')]
    [string]$OrgName = $(if ($env:ADO_ORG_NAME) { $env:ADO_ORG_NAME } else { $env:ADO_ORG_URL }),
    [string]$Project = $(if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { 'Contoso Logistics' }),
    [switch]$ResetStates
)
. "$PSScriptRoot/Common.ps1"

# Sprint -> Target Release mapping, shared by seeding and by -ResetStates.
$script:SprintToRelease = @{ 'Sprint 1' = '1.0.0'; 'Sprint 2' = '1.1.0'; 'Sprint 3' = '1.2.0' }

# ---- Logistics work items ---------------------------------------------------
# State mapping: New/Refinement/Ready for Dev -> New | Active -> Active
#               In QA/Ready for Merge -> Ready for Release | Closed -> Closed
$Epics = @(
    @{ title = 'Order Tracking Platform'; features = @(
        @{ title = 'Real-time Shipment Visibility'; stories = @(
            @{ title='Track shipment location on a live map'; state='Active';            area='App'; sprint='Sprint 1'; points=5 },
            @{ title='Show estimated delivery window';        state='Ready for Release'; area='App'; sprint='Sprint 2'; points=3 },
            @{ title='Surface delivery exceptions';           state='Ready for Release'; area='QA';  sprint='Sprint 2'; points=5 },
            @{ title='Push status changes to the timeline';   state='Active';    area='App'; sprint='Sprint 2'; points=3 }
        )},
        @{ title = 'Customer Notifications'; stories = @(
            @{ title='Email on out-for-delivery';             state='New';       area='App'; sprint='Sprint 2'; points=3 },
            @{ title='SMS opt-in and preferences';            state='New';       area='App'; sprint='Sprint 3'; points=5 },
            @{ title='Notification audit log';                state='New';       area='QA';  sprint='Sprint 3'; points=2 }
        )},
        @{ title = 'Carrier Integrations'; stories = @(
            @{ title='Normalize carrier tracking webhooks';   state='Active';    area='App'; sprint='Sprint 2'; points=8 },
            @{ title='Retry failed carrier callbacks';        state='New';       area='App'; sprint='Sprint 3'; points=5 },
            @{ title='Carrier SLA dashboard feed';            state='New';       area='QA';  sprint='Sprint 3'; points=3 }
        )}
    )},
    @{ title = 'Warehouse Automation'; features = @(
        @{ title = 'Automated Putaway'; stories = @(
            @{ title='Suggest optimal bin on receipt';        state='Active';            area='App'; sprint='Sprint 1'; points=5 },
            @{ title='Validate putaway with handheld scan';   state='Ready for Release'; area='QA';  sprint='Sprint 2'; points=3 },
            @{ title='Reslot slow-moving SKUs nightly';       state='Ready for Release'; area='QA';  sprint='Sprint 2'; points=5 },
            @{ title='Putaway exception queue';               state='New';       area='App'; sprint='Sprint 3'; points=3 }
        )},
        @{ title = 'Pick-and-Pack Optimization'; stories = @(
            @{ title='Batch picks by zone';                   state='Active';    area='App'; sprint='Sprint 2'; points=8 },
            @{ title='Cartonization recommendations';         state='New';       area='App'; sprint='Sprint 3'; points=5 },
            @{ title='Pack station throughput metrics';       state='New';       area='QA';  sprint='Sprint 3'; points=3 },
            @{ title='Short-pick rebalancing';                state='New';       area='App'; sprint='Sprint 3'; points=5 }
        )}
    )},
    # ---- DevOps & Platform Engineering epic -----------------------------------
    @{ title = 'DevOps & Platform Engineering'; features = @(
        @{ title = 'CI/CD Pipelines'; stories = @(
            @{ title='Set up build and unit-test pipeline';   state='Active';            area='DevOps'; sprint='Sprint 1'; points=5 },
            @{ title='Add automated deploy to staging';       state='Ready for Release'; area='DevOps'; sprint='Sprint 2'; points=5 },
            @{ title='Implement blue/green production release'; state='Active';  area='DevOps'; sprint='Sprint 2'; points=8 },
            @{ title='Add pipeline status badge to repo README'; state='Active'; area='DevOps'; sprint='Sprint 1'; points=2 }
        )},
        @{ title = 'Infrastructure as Code'; stories = @(
            @{ title='Provision dev/staging environments with IaC'; state='Active';  area='DevOps'; sprint='Sprint 2'; points=8 },
            @{ title='Containerize the application';               state='New';      area='DevOps'; sprint='Sprint 3'; points=5 },
            @{ title='Centralize config and secrets management';   state='New';      area='DevOps'; sprint='Sprint 3'; points=5 },
            @{ title='Automate environment teardown on PR close';  state='New';      area='DevOps'; sprint='Sprint 3'; points=3 }
        )},
        @{ title = 'Observability & Reliability'; stories = @(
            @{ title='Integrate centralized logging and metrics';   state='Active';  area='DevOps'; sprint='Sprint 2'; points=5 },
            @{ title='Add health-check endpoints and alerts';       state='New';     area='DevOps'; sprint='Sprint 3'; points=3 },
            @{ title='Build on-call runbook for common incidents';  state='New';     area='DevOps'; sprint='Sprint 3'; points=3 },
            @{ title='Set up distributed tracing';                  state='New';     area='DevOps'; sprint='Sprint 3'; points=5 }
        )},
        @{ title = 'Security & Compliance'; stories = @(
            @{ title='Add dependency and container vulnerability scanning'; state='Ready for Release'; area='DevOps'; sprint='Sprint 2'; points=5 },
            @{ title='Enable secret scanning in CI pipeline';               state='Active';            area='DevOps'; sprint='Sprint 1'; points=3 },
            @{ title='Automate SBOM generation on release';                 state='New';      area='DevOps'; sprint='Sprint 3'; points=5 },
            @{ title='Review and harden container base images';             state='New';      area='DevOps'; sprint='Sprint 3'; points=3 }
        )}
    )}
)

$Dependencies = @(
    # Logistics
    @{ pred = 'Track shipment location on a live map'; succ = 'Show estimated delivery window' },
    @{ pred = 'Suggest optimal bin on receipt';        succ = 'Validate putaway with handheld scan' },
    @{ pred = 'Normalize carrier tracking webhooks';   succ = 'Retry failed carrier callbacks' },
    @{ pred = 'Batch picks by zone';                   succ = 'Cartonization recommendations' },
    # DevOps
    @{ pred = 'Set up build and unit-test pipeline';   succ = 'Add automated deploy to staging' },
    @{ pred = 'Containerize the application';          succ = 'Add automated deploy to staging' },
    @{ pred = 'Provision dev/staging environments with IaC'; succ = 'Automate environment teardown on PR close' }
)

function Get-ExistingTitles {
    $wiql = @{ query = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject]='$($script:Project)'" }
    $res = Invoke-Ado POST (Get-ProjUrl 'wit/wiql') $wiql
    $ids = @($res.workItems | ForEach-Object { $_.id })
    $map = @{}
    for ($i = 0; $i -lt $ids.Count; $i += 200) {
        $batch = $ids[$i..([Math]::Min($i + 199, $ids.Count - 1))]
        if (-not $batch) { continue }
        $items = (Invoke-Ado GET (Get-ProjUrl "wit/workitems?ids=$($batch -join ',')&fields=System.Title")).value
        foreach ($it in $items) { $map[$it.fields.'System.Title'] = $it.id }
    }
    return $map
}

function New-WorkItem { param([string]$Type, $Fields, [string]$ParentUrl)
    $ops = @()
    foreach ($k in $Fields.Keys) { $ops += @{ op = 'add'; path = "/fields/$k"; value = $Fields[$k] } }
    if ($ParentUrl) { $ops += @{ op = 'add'; path = '/relations/-'; value = @{ rel = 'System.LinkTypes.Hierarchy-Reverse'; url = $ParentUrl } } }
    $t = [uri]::EscapeDataString($Type)
    Invoke-Ado POST (Get-ProjUrl "wit/workitems/`$$t") (ConvertTo-JsonArray $ops) 'application/json-patch+json'
}

# Agile states require stepping through categories; ADO won't allow jumping
# directly from New to a resolved-category or completed state.
function Set-State { param([int]$Id, [string]$State)
    $steps = switch ($State) {
        'Active'            { @('Active') }
        'Ready for Release' { @('Active', 'Ready for Release') }
        'Resolved'          { @('Active', 'Resolved') }
        'Closed'            { @('Active', 'Ready for Release', 'Closed') }
        default             { @() }
    }
    foreach ($step in $steps) {
        $ops = @(@{ op = 'add'; path = '/fields/System.State'; value = $step })
        Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$Id") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
    }
}

function Add-Dependency { param($Have, [string]$Pred, [string]$Succ)
    if (-not $Have.ContainsKey($Pred) -or -not $Have.ContainsKey($Succ)) { Write-Host "  dep skip (missing): $Pred -> $Succ"; return }
    $predWi = Invoke-Ado GET (Get-ProjUrl "wit/workitems/$($Have[$Pred])?`$expand=relations")
    $succUrl = (Invoke-Ado GET (Get-ProjUrl "wit/workitems/$($Have[$Succ])")).url
    foreach ($rel in @($predWi.relations)) {
        if ($rel.rel -eq 'System.LinkTypes.Dependency-Forward' -and $rel.url -eq $succUrl) { Write-Host "  dep exists: $Pred -> $Succ"; return }
    }
    $ops = @(@{ op = 'add'; path = '/relations/-'; value = @{ rel = 'System.LinkTypes.Dependency-Forward'; url = $succUrl } })
    Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$($Have[$Pred])") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
    Write-Host "  + dependency: $Pred -> $Succ"
}

# Force-PATCH a story back to its declared baseline state AND Target Release,
# regardless of current values. Used only by -ResetStates. Unlike Set-State
# (creation-time, forward-only stepping), this may need to jump backwards (e.g.
# Closed -> New), so it PATCHes the target state directly rather than walking
# intermediate steps. Target Release is included because the release-tracking
# demo has a product owner retarget a story live (LAB-GUIDE.md §8.4) — without
# this, that edit would survive every subsequent reset. Report — don't throw —
# on rejection, since a demo reset must never hard-fail on one story.
function Set-StateForce { param([int]$Id, [string]$State, [string]$TargetRelease)
    try {
        $ops = @(@{ op = 'add'; path = '/fields/System.State'; value = $State })
        if ($TargetRelease) { $ops += @{ op = 'add'; path = '/fields/Custom.TargetRelease'; value = $TargetRelease } }
        Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$Id") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
        return $true
    } catch {
        Write-Warning "  could not reset #$Id to '$State': $($_.Exception.Message)"
        return $false
    }
}

$P = $script:Project
$have = Get-ExistingTitles
Write-Host "Existing work items: $($have.Count)"

if ($ResetStates) {
    Write-Host 'Resetting seeded story states and Target Release to their declared baseline values...'
    $reset = 0; $failed = 0; $skipped = 0
    foreach ($epic in $Epics) {
        foreach ($feat in $epic.features) {
            foreach ($s in $feat.stories) {
                if (-not $have.ContainsKey($s.title)) { $skipped++; continue }
                $target = $script:SprintToRelease[$s.sprint]
                if (Set-StateForce $have[$s.title] $s.state $target) {
                    Write-Host "  reset: $($s.title) -> $($s.state) / $target"
                    $reset++
                } else { $failed++ }
            }
        }
    }
    Write-Host "Done. reset=$reset failed=$failed skipped(not found)=$skipped"
    return
}

function Ensure-Wi { param([string]$Type, [string]$Title, $Fields, [string]$ParentUrl)
    if ($have.ContainsKey($Title)) {
        $id = $have[$Title]
        # Backfill: an environment provisioned before Custom.TargetRelease existed
        # won't have it on already-created stories. Patch it in without touching
        # anything else, so re-running after an upgrade converges cleanly.
        if ($Type -eq 'User Story' -and $Fields.ContainsKey('Custom.TargetRelease')) {
            $wi = Invoke-Ado GET (Get-ProjUrl "wit/workitems/$id")
            if (-not $wi.fields.'Custom.TargetRelease') {
                $ops = @(@{ op = 'add'; path = '/fields/Custom.TargetRelease'; value = $Fields['Custom.TargetRelease'] })
                Invoke-Ado PATCH (Get-ProjUrl "wit/workitems/$id") (ConvertTo-JsonArray $ops) 'application/json-patch+json' | Out-Null
                Write-Host "  ~ backfilled Custom.TargetRelease on: $Title"
            }
        }
        Write-Host "  exists: [$Type] $Title"; return (Invoke-Ado GET (Get-ProjUrl "wit/workitems/$id")).url
    }
    $target = $null
    if ($Fields.ContainsKey('System.State')) { $target = $Fields['System.State']; $Fields.Remove('System.State') }
    $Fields['System.Title'] = $Title
    $wi = New-WorkItem $Type $Fields $ParentUrl
    if ($target -and $target -ne 'New') { Set-State $wi.id $target }
    $have[$Title] = $wi.id
    Write-Host "  + [$Type] $Title (#$($wi.id)) -> $(if ($target) { $target } else { 'New' })"
    return $wi.url
}

foreach ($epic in $Epics) {
    $eurl = Ensure-Wi 'Epic' $epic.title (@{ 'System.AreaPath' = $P; 'System.State' = 'Active' })
    foreach ($feat in $epic.features) {
        $furl = Ensure-Wi 'Feature' $feat.title (@{ 'System.AreaPath' = $P; 'System.State' = 'Active' }) $eurl
        foreach ($s in $feat.stories) {
            $fields = @{
                'System.AreaPath'      = "$P\$($s.area)"
                'System.IterationPath' = "$P\$($s.sprint)"
                'System.State'         = $s.state
                'Microsoft.VSTS.Scheduling.StoryPoints' = $s.points
                'Custom.TargetRelease' = $script:SprintToRelease[$s.sprint]
            }
            Ensure-Wi 'User Story' $s.title $fields $furl | Out-Null
        }
    }
}

Write-Host 'Dependencies:'
foreach ($d in $Dependencies) { Add-Dependency $have $d.pred $d.succ }
Write-Host 'Done.'
