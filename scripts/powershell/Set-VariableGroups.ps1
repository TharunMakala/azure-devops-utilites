<#
.SYNOPSIS
    Create or update Azure DevOps variable groups, optionally linked to Azure Key Vault.

.DESCRIPTION
    Manages variable groups in Azure DevOps. Supports plain variables and
    Key Vault-linked variable groups where secrets are sourced from Azure Key Vault.

.PARAMETER Organization
    Azure DevOps organization name.

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER GroupName
    Name of the variable group to create or update.

.PARAMETER Variables
    Hashtable of variable name → value pairs for plain variable groups.
    Mark a value as secret by wrapping it: @{ MY_SECRET = @{ value = "s3cr3t"; isSecret = $true } }

.PARAMETER KeyVaultName
    Azure Key Vault name. When provided, creates a Key Vault-linked group.

.PARAMETER KeyVaultServiceConnection
    Azure service connection with Key Vault access (required for KV-linked groups).

.PARAMETER SecretsToLink
    Array of Key Vault secret names to surface in the variable group.

.PARAMETER PersonalAccessToken
    PAT with "Variable Groups > Read, Create & Manage" scope.

.EXAMPLE
    # Create a plain variable group
    $vars = @{
        BUILD_ENV = @{ value = "production"; isSecret = $false }
        API_KEY   = @{ value = "abc123";     isSecret = $true  }
    }
    .\Set-VariableGroups.ps1 -Organization myorg -Project MyProject `
        -GroupName "MyAppVars" -Variables $vars -PersonalAccessToken $env:ADO_PAT

.EXAMPLE
    # Create a Key Vault-linked variable group
    .\Set-VariableGroups.ps1 -Organization myorg -Project MyProject `
        -GroupName "MyAppSecrets" `
        -KeyVaultName "my-keyvault" `
        -KeyVaultServiceConnection "AzureServiceConnection" `
        -SecretsToLink @("DatabasePassword", "ApiSecret") `
        -PersonalAccessToken $env:ADO_PAT
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Plain')]
param (
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [Parameter(Mandatory)] [string] $GroupName,

    [Parameter(ParameterSetName = 'Plain')]
    [hashtable] $Variables = @{},

    [Parameter(ParameterSetName = 'KeyVault', Mandatory)]
    [string] $KeyVaultName,

    [Parameter(ParameterSetName = 'KeyVault', Mandatory)]
    [string] $KeyVaultServiceConnection,

    [Parameter(ParameterSetName = 'KeyVault')]
    [string[]] $SecretsToLink = @(),

    [string] $PersonalAccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiParams = @{
    Organization        = $Organization
    PersonalAccessToken = $PersonalAccessToken
}

#region ── Build request body ─────────────────────────────────────────────────
if ($PSCmdlet.ParameterSetName -eq 'Plain') {
    # Normalize variables hashtable
    $vars = @{}
    foreach ($key in $Variables.Keys) {
        $val = $Variables[$key]
        if ($val -is [hashtable]) {
            $vars[$key] = @{ value = $val.value; isSecret = [bool]$val.isSecret }
        }
        else {
            $vars[$key] = @{ value = "$val"; isSecret = $false }
        }
    }

    $body = @{
        name      = $GroupName
        type      = 'Vsts'
        variables = $vars
    }
}
else {
    # Key Vault-linked group
    $secrets = $SecretsToLink | ForEach-Object { @{ name = $_ } }
    $body = @{
        name            = $GroupName
        type            = 'AzureKeyVault'
        keyVaultName    = $KeyVaultName
        providerData    = @{
            serviceEndpointId   = $KeyVaultServiceConnection
            vault               = $KeyVaultName
        }
        variables       = @{}
        variableGroupProjectReferences = @(
            @{ name = $GroupName; projectReference = @{ name = $Project } }
        )
    }
    # Add secrets as empty variable entries (ADO will pull values from KV)
    foreach ($secret in $SecretsToLink) {
        $body.variables[$secret] = @{ isSecret = $true; enabled = $true }
    }
}
#endregion

#region ── Check for existing group ───────────────────────────────────────────
$existing = (.\Invoke-AzureDevOpsApi.ps1 @apiParams `
    -ApiPath "/$Project/_apis/distributedtask/variablegroups?api-version=7.1").value |
    Where-Object { $_.name -eq $GroupName }

if ($existing) {
    # Update existing group
    $body['id'] = $existing.id
    if ($PSCmdlet.ShouldProcess($GroupName, 'Update variable group')) {
        Write-Host "Updating variable group '$GroupName' (ID: $($existing.id))..." -ForegroundColor Cyan
        .\Invoke-AzureDevOpsApi.ps1 @apiParams `
            -ApiPath "/$Project/_apis/distributedtask/variablegroups/$($existing.id)?api-version=7.1" `
            -Method PUT `
            -Body $body | Out-Null
        Write-Host "Variable group '$GroupName' updated." -ForegroundColor Green
    }
}
else {
    # Create new group
    if ($PSCmdlet.ShouldProcess($GroupName, 'Create variable group')) {
        Write-Host "Creating variable group '$GroupName'..." -ForegroundColor Cyan
        $result = .\Invoke-AzureDevOpsApi.ps1 @apiParams `
            -ApiPath "/$Project/_apis/distributedtask/variablegroups?api-version=7.1" `
            -Method POST `
            -Body $body
        Write-Host "Variable group '$GroupName' created (ID: $($result.id))." -ForegroundColor Green
    }
}
#endregion
