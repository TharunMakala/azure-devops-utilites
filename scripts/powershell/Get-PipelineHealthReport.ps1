<#
.SYNOPSIS
    Builds a pipeline-health report for an Azure DevOps project over a rolling window.

.DESCRIPTION
    Pulls completed build runs from the Builds REST API for the last N days, groups
    them by definition, and computes:
        - total runs, success rate, failure rate, cancel rate
        - duration p50 / p95 (minutes)
        - flakiness score: share of definitions with alternating pass/fail on the same
          source version within the window
        - top 5 slowest and top 5 most-failing pipelines

    Emits a JSON report always, and an optional self-contained HTML report you can
    drop on a wiki or attach to a PR.

.PARAMETER Organization
    Azure DevOps organization slug.

.PARAMETER Project
    Project name to report on.

.PARAMETER Days
    Rolling window in days. Default 14.

.PARAMETER OutputDirectory
    Where to write pipeline-health.json and (optionally) pipeline-health.html.
    Defaults to ./reports.

.PARAMETER AsHtml
    When set, also writes an HTML report alongside the JSON.

.PARAMETER PersonalAccessToken
    PAT with "Build > Read" scope. Falls back to az CLI token when omitted.

.EXAMPLE
    .\Get-PipelineHealthReport.ps1 `
        -Organization myorg `
        -Project Platform `
        -Days 30 `
        -AsHtml `
        -PersonalAccessToken $env:ADO_PAT
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [int]    $Days             = 14,
    [string] $OutputDirectory  = './reports',
    [switch] $AsHtml,
    [string] $PersonalAccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiParams = @{
    Organization        = $Organization
    PersonalAccessToken = $PersonalAccessToken
}

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('o')
Write-Host "Collecting builds for '$Project' since $since ..." -ForegroundColor Cyan

# ── Paginate /_apis/build/builds ───────────────────────────────────────────────
$builds        = [System.Collections.Generic.List[object]]::new()
$continuation  = $null
do {
    $path = "/$Project/_apis/build/builds?api-version=7.1&minTime=$since&statusFilter=completed&`$top=500"
    if ($continuation) { $path += "&continuationToken=$continuation" }

    $page = .\Invoke-AzureDevOpsApi.ps1 @apiParams -ApiPath $path
    if ($page.value) { $builds.AddRange($page.value) }

    $continuation = $page.PSObject.Properties['continuationToken']?.Value
} while ($continuation)

Write-Host "Pulled $($builds.Count) build runs." -ForegroundColor Cyan
if ($builds.Count -eq 0) {
    Write-Warning "No builds in the window — nothing to report."
    return
}

# ── Aggregate per definition ──────────────────────────────────────────────────
function Get-Percentile {
    param([double[]] $Values, [int] $P)
    if (-not $Values -or $Values.Count -eq 0) { return 0 }
    $sorted = $Values | Sort-Object
    $idx    = [int][math]::Ceiling(($P / 100.0) * $sorted.Count) - 1
    if ($idx -lt 0) { $idx = 0 }
    return [math]::Round($sorted[$idx], 2)
}

$byDef = $builds | Group-Object { $_.definition.id }

$perPipeline = foreach ($grp in $byDef) {
    $runs        = $grp.Group
    $def         = $runs[0].definition
    $durations   = $runs | ForEach-Object {
        if ($_.startTime -and $_.finishTime) {
            ([datetime]$_.finishTime - [datetime]$_.startTime).TotalMinutes
        }
    } | Where-Object { $_ -gt 0 }

    # Flaky: same sourceVersion observed with both succeeded and failed results
    $flakyVersions = $runs |
        Group-Object sourceVersion |
        Where-Object {
            ($_.Group.result -contains 'succeeded') -and
            ($_.Group.result -contains 'failed')
        }

    [pscustomobject]@{
        id            = $def.id
        name          = $def.name
        path          = $def.path
        runs          = $runs.Count
        succeeded     = ($runs | Where-Object result -EQ 'succeeded').Count
        failed        = ($runs | Where-Object result -EQ 'failed').Count
        canceled      = ($runs | Where-Object result -EQ 'canceled').Count
        successRate   = if ($runs.Count) { [math]::Round(($runs | Where-Object result -EQ 'succeeded').Count / $runs.Count, 3) } else { 0 }
        p50Minutes    = Get-Percentile -Values $durations -P 50
        p95Minutes    = Get-Percentile -Values $durations -P 95
        flakyVersions = $flakyVersions.Count
    }
}

$totalRuns      = ($perPipeline | Measure-Object runs      -Sum).Sum
$totalSucceeded = ($perPipeline | Measure-Object succeeded -Sum).Sum
$totalFailed    = ($perPipeline | Measure-Object failed    -Sum).Sum
$totalCanceled  = ($perPipeline | Measure-Object canceled  -Sum).Sum

$report = [pscustomobject]@{
    generatedAt  = (Get-Date).ToUniversalTime().ToString('o')
    organization = $Organization
    project      = $Project
    windowDays   = $Days
    summary      = [pscustomobject]@{
        totalRuns     = $totalRuns
        succeeded     = $totalSucceeded
        failed        = $totalFailed
        canceled      = $totalCanceled
        successRate   = if ($totalRuns) { [math]::Round($totalSucceeded / $totalRuns, 3) } else { 0 }
    }
    slowestTop5  = $perPipeline | Sort-Object p95Minutes   -Descending | Select-Object -First 5
    failingTop5  = $perPipeline | Sort-Object successRate             | Select-Object -First 5
    pipelines    = $perPipeline | Sort-Object name
}

# ── Emit ───────────────────────────────────────────────────────────────────────
$outDir = New-Item -ItemType Directory -Path $OutputDirectory -Force
$jsonPath = Join-Path $outDir.FullName 'pipeline-health.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
Write-Host "JSON report: $jsonPath" -ForegroundColor Green

if ($AsHtml) {
    $rows = ($report.pipelines | ForEach-Object {
        $sr = '{0:P1}' -f $_.successRate
        $cls = if ($_.successRate -lt 0.8) { 'bad' } elseif ($_.successRate -lt 0.95) { 'warn' } else { 'ok' }
        "<tr class='$cls'><td>$($_.name)</td><td>$($_.runs)</td><td>$sr</td><td>$($_.p50Minutes)</td><td>$($_.p95Minutes)</td><td>$($_.flakyVersions)</td></tr>"
    }) -join "`n"

    $html = @"
<!doctype html>
<meta charset="utf-8">
<title>Pipeline health — $Project</title>
<style>
body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:2rem;color:#222}
h1{margin-bottom:0}.sub{color:#666;margin-top:.25rem}
table{border-collapse:collapse;margin-top:1.5rem;width:100%}
th,td{padding:.5rem .75rem;border-bottom:1px solid #eee;text-align:left}
th{background:#f6f8fa}
tr.bad td{background:#ffecec}tr.warn td{background:#fff6e5}tr.ok td{background:#f1fff1}
.kpi{display:inline-block;margin-right:2rem}
.kpi b{font-size:1.4rem}
</style>
<h1>Pipeline health — $Project</h1>
<p class="sub">Window: last $Days days &middot; generated $($report.generatedAt)</p>
<div class="kpi"><div>Total runs</div><b>$totalRuns</b></div>
<div class="kpi"><div>Success rate</div><b>$('{0:P1}' -f $report.summary.successRate)</b></div>
<div class="kpi"><div>Failed</div><b>$totalFailed</b></div>
<div class="kpi"><div>Canceled</div><b>$totalCanceled</b></div>
<table>
  <tr><th>Pipeline</th><th>Runs</th><th>Success rate</th><th>p50 (min)</th><th>p95 (min)</th><th>Flaky versions</th></tr>
  $rows
</table>
"@
    $htmlPath = Join-Path $outDir.FullName 'pipeline-health.html'
    $html | Set-Content -Path $htmlPath -Encoding UTF8
    Write-Host "HTML report: $htmlPath" -ForegroundColor Green
}

return $report
