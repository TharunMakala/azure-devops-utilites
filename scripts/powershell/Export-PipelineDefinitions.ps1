<#
.SYNOPSIS
    Exports all pipeline definitions from an Azure DevOps project to local YAML files.

.DESCRIPTION
    Iterates through all pipelines in the specified project and saves their
    YAML content to a local directory, preserving the pipeline folder hierarchy.

.PARAMETER Organization
    Azure DevOps organization name.

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER OutputDirectory
    Local directory where exported YAML files will be saved. Created if absent.

.PARAMETER PersonalAccessToken
    PAT with "Build > Read" scope.

.EXAMPLE
    .\Export-PipelineDefinitions.ps1 `
        -Organization myorg `
        -Project MyProject `
        -OutputDirectory ./exported-pipelines `
        -PersonalAccessToken $env:ADO_PAT
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [string] $OutputDirectory     = './exported-pipelines',
    [string] $PersonalAccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiParams = @{
    Organization        = $Organization
    PersonalAccessToken = $PersonalAccessToken
}

# Ensure output directory exists
$outDir = New-Item -ItemType Directory -Path $OutputDirectory -Force
Write-Host "Exporting pipelines to: $($outDir.FullName)" -ForegroundColor Cyan

# Fetch all pipeline definitions
$definitions = (.\Invoke-AzureDevOpsApi.ps1 @apiParams `
    -ApiPath "/$Project/_apis/build/definitions?api-version=7.1&`$top=500").value

Write-Host "Found $($definitions.Count) pipeline(s)." -ForegroundColor Cyan

$exported = 0
$failed   = 0

foreach ($def in $definitions) {
    try {
        # Get full definition including YAML
        $full = .\Invoke-AzureDevOpsApi.ps1 @apiParams `
            -ApiPath "/$Project/_apis/build/definitions/$($def.id)?api-version=7.1"

        # Determine safe file name preserving folder path
        $folderPath = ($full.path -replace '^\\', '' -replace '\\', '/').Trim('/')
        $safeName   = $full.name -replace '[<>:"/\\|?*]', '_'
        $fileName   = if ($folderPath) { "$folderPath/$safeName.yml" } else { "$safeName.yml" }
        $filePath   = Join-Path $outDir.FullName $fileName

        # Create subdirectory if needed
        $fileDir = Split-Path $filePath -Parent
        if (-not (Test-Path $fileDir)) {
            New-Item -ItemType Directory -Path $fileDir -Force | Out-Null
        }

        # Write YAML content or definition JSON if YAML not available
        if ($full.process.yamlFilename) {
            # Pipeline references a YAML file in the repo — record the reference
            $content = @"
# Pipeline: $($full.name)
# YAML file: $($full.process.yamlFilename)
# Repository: $($full.repository.name)
# Branch: $($full.repository.defaultBranch)
# Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
            Set-Content -Path $filePath -Value $content -Encoding UTF8
        }
        else {
            # Classic pipeline — export as JSON
            $filePath = $filePath -replace '\.yml$', '.json'
            $full | ConvertTo-Json -Depth 20 | Set-Content -Path $filePath -Encoding UTF8
        }

        Write-Host "  [OK] $fileName" -ForegroundColor Green
        $exported++
    }
    catch {
        Write-Warning "  [FAIL] $($def.name): $_"
        $failed++
    }
}

Write-Host "`nExport complete. Exported: $exported  Failed: $failed" -ForegroundColor Cyan
