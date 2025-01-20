<#
.SYNOPSIS
    Generates Azure cost reports for DevOps-related resources.

.DESCRIPTION
    Queries Azure Cost Management API to produce cost breakdowns by resource group,
    service, and tag. Supports budget alerts and trend analysis.

.PARAMETER SubscriptionId
    Azure subscription ID to query.

.PARAMETER DaysBack
    Number of days to include in the report (default: 30).

.PARAMETER ResourceGroupFilter
    Optional regex filter for resource group names.

.PARAMETER OutputFormat
    Output format: Table, CSV, or JSON (default: Table).

.PARAMETER BudgetThreshold
    Alert threshold as percentage of monthly budget (default: 80).

.EXAMPLE
    .\Get-AzureCostReport.ps1 -SubscriptionId "xxx" -DaysBack 7 -OutputFormat CSV
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [int]$DaysBack = 30,

    [string]$ResourceGroupFilter = ".*devops.*|.*agent.*|.*pipeline.*",

    [ValidateSet("Table", "CSV", "JSON")]
    [string]$OutputFormat = "Table",

    [int]$BudgetThreshold = 80,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-AzureAccessToken {
    try {
        $token = az account get-access-token --query accessToken -o tsv 2>$null
        if (-not $token) {
            throw "Not logged in"
        }
        return $token
    }
    catch {
        Write-Error "Azure CLI authentication required. Run 'az login' first."
        exit 1
    }
}

function Invoke-CostManagementQuery {
    param(
        [string]$Token,
        [string]$SubscriptionId,
        [hashtable]$Body
    )

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-11-01"

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ($Body | ConvertTo-Json -Depth 10)
    return $response
}

function Get-CostByResourceGroup {
    param([string]$Token, [string]$SubscriptionId, [datetime]$StartDate, [datetime]$EndDate)

    $body = @{
        type       = "ActualCost"
        timeframe  = "Custom"
        timePeriod = @{
            from = $StartDate.ToString("yyyy-MM-dd")
            to   = $EndDate.ToString("yyyy-MM-dd")
        }
        dataset    = @{
            granularity = "None"
            aggregation = @{
                totalCost = @{ name = "Cost"; function = "Sum" }
            }
            grouping    = @(
                @{ type = "Dimension"; name = "ResourceGroupName" }
            )
        }
    }

    return Invoke-CostManagementQuery -Token $Token -SubscriptionId $SubscriptionId -Body $body
}

function Get-CostByService {
    param([string]$Token, [string]$SubscriptionId, [datetime]$StartDate, [datetime]$EndDate)

    $body = @{
        type       = "ActualCost"
        timeframe  = "Custom"
        timePeriod = @{
            from = $StartDate.ToString("yyyy-MM-dd")
            to   = $EndDate.ToString("yyyy-MM-dd")
        }
        dataset    = @{
            granularity = "None"
            aggregation = @{
                totalCost = @{ name = "Cost"; function = "Sum" }
            }
            grouping    = @(
                @{ type = "Dimension"; name = "ServiceName" }
            )
        }
    }

    return Invoke-CostManagementQuery -Token $Token -SubscriptionId $SubscriptionId -Body $body
}

function Get-DailyCostTrend {
    param([string]$Token, [string]$SubscriptionId, [datetime]$StartDate, [datetime]$EndDate)

    $body = @{
        type       = "ActualCost"
        timeframe  = "Custom"
        timePeriod = @{
            from = $StartDate.ToString("yyyy-MM-dd")
            to   = $EndDate.ToString("yyyy-MM-dd")
        }
        dataset    = @{
            granularity = "Daily"
            aggregation = @{
                totalCost = @{ name = "Cost"; function = "Sum" }
            }
        }
    }

    return Invoke-CostManagementQuery -Token $Token -SubscriptionId $SubscriptionId -Body $body
}

function Format-CostData {
    param($Response, [string]$GroupByColumn = "ResourceGroupName")

    $columns = $Response.properties.columns
    $rows = $Response.properties.rows

    $costIdx = ($columns | Where-Object { $_.name -eq "Cost" }).type -ne $null ? 0 : 0
    $groupIdx = 1
    $currencyIdx = 2

    $results = foreach ($row in $rows) {
        [PSCustomObject]@{
            Name     = $row[$groupIdx]
            Cost     = [math]::Round($row[$costIdx], 2)
            Currency = $row[$currencyIdx]
        }
    }

    return $results | Sort-Object -Property Cost -Descending
}

# Main execution
Write-Host "`n=== Azure DevOps Cost Report ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId"
Write-Host "Period: Last $DaysBack days`n"

$token = Get-AzureAccessToken
$endDate = (Get-Date).Date
$startDate = $endDate.AddDays(-$DaysBack)

# Cost by Resource Group
Write-Host "Fetching costs by resource group..." -ForegroundColor Yellow
$rgCosts = Get-CostByResourceGroup -Token $token -SubscriptionId $SubscriptionId -StartDate $startDate -EndDate $endDate
$rgData = Format-CostData -Response $rgCosts

if ($ResourceGroupFilter) {
    $rgData = $rgData | Where-Object { $_.Name -match $ResourceGroupFilter }
}

$totalCost = ($rgData | Measure-Object -Property Cost -Sum).Sum

Write-Host "`n--- Cost by Resource Group ---" -ForegroundColor Green
switch ($OutputFormat) {
    "Table" { $rgData | Format-Table -AutoSize }
    "CSV" {
        $csvPath = if ($OutputPath) { $OutputPath } else { "cost-report-rg.csv" }
        $rgData | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "Exported to $csvPath"
    }
    "JSON" { $rgData | ConvertTo-Json }
}

# Cost by Service
Write-Host "Fetching costs by service..." -ForegroundColor Yellow
$svcCosts = Get-CostByService -Token $token -SubscriptionId $SubscriptionId -StartDate $startDate -EndDate $endDate
$svcData = Format-CostData -Response $svcCosts -GroupByColumn "ServiceName"

Write-Host "`n--- Cost by Service ---" -ForegroundColor Green
$svcData | Format-Table -AutoSize

# Daily trend
Write-Host "Fetching daily cost trend..." -ForegroundColor Yellow
$trendCosts = Get-DailyCostTrend -Token $token -SubscriptionId $SubscriptionId -StartDate $startDate -EndDate $endDate

$dailyAvg = [math]::Round($totalCost / $DaysBack, 2)
$projectedMonthly = [math]::Round($dailyAvg * 30, 2)

Write-Host "`n--- Summary ---" -ForegroundColor Green
Write-Host "Total Cost (${DaysBack}d):    `$$totalCost"
Write-Host "Daily Average:          `$$dailyAvg"
Write-Host "Projected Monthly:      `$$projectedMonthly"

if ($BudgetThreshold -gt 0) {
    $budgetUsage = [math]::Round(($projectedMonthly / 1000) * 100, 1)
    if ($budgetUsage -ge $BudgetThreshold) {
        Write-Warning "Projected cost ($projectedMonthly) exceeds ${BudgetThreshold}% of monthly budget!"
    }
}

Write-Host "`nReport generated at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
