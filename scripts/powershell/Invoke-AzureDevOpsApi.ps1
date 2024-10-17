<#
.SYNOPSIS
    Generic helper to call the Azure DevOps REST API with proper authentication.

.DESCRIPTION
    Wraps Invoke-RestMethod with Azure DevOps authentication (PAT or Azure CLI token),
    retry logic, and consistent error handling. Use this as the foundation for all
    custom ADO REST API integrations.

.PARAMETER Organization
    Azure DevOps organization name (e.g., "myorg" from https://dev.azure.com/myorg).

.PARAMETER ApiPath
    Relative API path after the organization, e.g. "/_apis/projects?api-version=7.1".

.PARAMETER Method
    HTTP method: GET, POST, PUT, PATCH, DELETE. Defaults to GET.

.PARAMETER Body
    Request body as a PowerShell object (will be serialized to JSON).

.PARAMETER PersonalAccessToken
    PAT with appropriate scopes. If omitted, falls back to an Azure CLI access token.

.PARAMETER MaxRetries
    Number of retry attempts on transient errors (429, 5xx). Defaults to 3.

.EXAMPLE
    # List all projects using a PAT
    $projects = .\Invoke-AzureDevOpsApi.ps1 `
        -Organization "myorg" `
        -ApiPath "/_apis/projects?api-version=7.1" `
        -PersonalAccessToken $env:ADO_PAT

.EXAMPLE
    # Create a new team using Azure CLI auth
    $body = @{ name = "New Team"; description = "Created via API" }
    .\Invoke-AzureDevOpsApi.ps1 `
        -Organization "myorg" `
        -ApiPath "/_apis/projects/MyProject/teams?api-version=7.1" `
        -Method POST `
        -Body $body
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $Organization,

    [Parameter(Mandatory)]
    [string] $ApiPath,

    [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
    [string] $Method = 'GET',

    [object] $Body,

    [string] $PersonalAccessToken,

    [int] $MaxRetries = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Authentication ──────────────────────────────────────────────────────
function Get-AuthHeader {
    if ($PersonalAccessToken) {
        $base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
        return @{ Authorization = "Basic $base64" }
    }

    # Fall back to Azure CLI token
    try {
        $tokenJson = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 2>&1
        $token = ($tokenJson | ConvertFrom-Json).accessToken
        return @{ Authorization = "Bearer $token" }
    }
    catch {
        throw "No PAT provided and Azure CLI authentication failed. Run 'az login' first."
    }
}
#endregion

#region ── Request ────────────────────────────────────────────────────────────
$baseUrl  = "https://dev.azure.com/$Organization"
$uri      = "$baseUrl$ApiPath"
$headers  = Get-AuthHeader
$headers['Content-Type'] = 'application/json'

$invokeParams = @{
    Uri     = $uri
    Method  = $Method
    Headers = $headers
}

if ($Body -and $Method -ne 'GET') {
    $invokeParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
}

$attempt  = 0
$response = $null

while ($attempt -le $MaxRetries) {
    $attempt++
    try {
        Write-Verbose "[$attempt/$($MaxRetries + 1)] $Method $uri"
        $response = Invoke-RestMethod @invokeParams
        break
    }
    catch [System.Net.WebException] {
        $statusCode = [int]$_.Exception.Response.StatusCode

        if ($statusCode -in @(429, 500, 502, 503, 504) -and $attempt -le $MaxRetries) {
            $delay = [math]::Pow(2, $attempt)   # Exponential back-off
            Write-Warning "HTTP $statusCode — retrying in ${delay}s (attempt $attempt of $MaxRetries)..."
            Start-Sleep -Seconds $delay
        }
        else {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            $message   = if ($errorBody.message) { $errorBody.message } else { $_.Exception.Message }
            throw "Azure DevOps API error (HTTP $statusCode): $message"
        }
    }
}
#endregion

return $response
