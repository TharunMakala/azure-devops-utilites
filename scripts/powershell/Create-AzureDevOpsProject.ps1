<#
.SYNOPSIS
    Creates a new Azure DevOps project with sensible defaults.

.DESCRIPTION
    Creates an ADO project with configurable version control, work item process,
    and visibility. Waits for the project to finish provisioning before returning.

.PARAMETER Organization
    Azure DevOps organization name.

.PARAMETER ProjectName
    Name of the new project. Must be unique within the organization.

.PARAMETER Description
    Optional project description.

.PARAMETER SourceControl
    Version control type: Git (default) or Tfvc.

.PARAMETER ProcessTemplate
    Work item process: Agile, Scrum, CMMI, or Basic. Defaults to Scrum.

.PARAMETER Visibility
    Project visibility: private (default) or public.

.PARAMETER PersonalAccessToken
    PAT with "Project and Team > Read & Write" scope.

.EXAMPLE
    .\Create-AzureDevOpsProject.ps1 `
        -Organization "myorg" `
        -ProjectName "MyNewProject" `
        -Description "Created by automation" `
        -ProcessTemplate Scrum `
        -PersonalAccessToken $env:ADO_PAT
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $ProjectName,
    [string]  $Description      = '',
    [ValidateSet('Git', 'Tfvc')]
    [string]  $SourceControl    = 'Git',
    [ValidateSet('Agile', 'Scrum', 'CMMI', 'Basic')]
    [string]  $ProcessTemplate  = 'Scrum',
    [ValidateSet('private', 'public')]
    [string]  $Visibility       = 'private',
    [string]  $PersonalAccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiParams = @{
    Organization       = $Organization
    PersonalAccessToken = $PersonalAccessToken
}

#region ── Resolve process template ID ────────────────────────────────────────
Write-Host "Resolving process template '$ProcessTemplate'..." -ForegroundColor Cyan
$processes   = .\Invoke-AzureDevOpsApi.ps1 @apiParams -ApiPath '/_apis/process/processes?api-version=7.1'
$processId   = ($processes.value | Where-Object { $_.name -eq $ProcessTemplate }).id

if (-not $processId) {
    throw "Process template '$ProcessTemplate' not found in organization '$Organization'."
}
Write-Host "  Process ID: $processId" -ForegroundColor Gray
#endregion

#region ── Create project ─────────────────────────────────────────────────────
$body = @{
    name         = $ProjectName
    description  = $Description
    visibility   = $Visibility
    capabilities = @{
        versioncontrol  = @{ sourceControlType = $SourceControl }
        processTemplate = @{ templateTypeId    = $processId }
    }
}

if ($PSCmdlet.ShouldProcess($ProjectName, 'Create Azure DevOps project')) {
    Write-Host "Creating project '$ProjectName'..." -ForegroundColor Cyan
    $result = .\Invoke-AzureDevOpsApi.ps1 @apiParams `
        -ApiPath '/_apis/projects?api-version=7.1' `
        -Method POST `
        -Body $body

    $operationUrl = $result.url
    Write-Host "  Operation URL: $operationUrl" -ForegroundColor Gray

    # Poll until the project is provisioned
    $timeout  = (Get-Date).AddMinutes(5)
    $interval = 3
    do {
        Start-Sleep -Seconds $interval
        $status = Invoke-RestMethod -Uri $operationUrl -Headers @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken")))" }
        Write-Host "  Status: $($status.status)" -ForegroundColor Gray

        if ($status.status -eq 'failed') {
            throw "Project creation failed: $($status.resultMessage)"
        }
    } while ($status.status -ne 'succeeded' -and (Get-Date) -lt $timeout)

    if ($status.status -ne 'succeeded') {
        throw "Project creation timed out after 5 minutes."
    }

    Write-Host "Project '$ProjectName' created successfully!" -ForegroundColor Green
    Write-Host "URL: https://dev.azure.com/$Organization/$ProjectName" -ForegroundColor Green
}
#endregion
