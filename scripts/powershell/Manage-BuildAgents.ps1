<#
.SYNOPSIS
    List, register, or remove self-hosted build agents in an agent pool.

.DESCRIPTION
    Provides agent lifecycle management via the Azure DevOps REST API.
    Supports listing all agents in a pool, checking agent status,
    and deleting offline/unauthorized agents.

.PARAMETER Organization
    Azure DevOps organization name.

.PARAMETER PoolName
    Agent pool name to manage.

.PARAMETER Action
    Action to perform: List, DeleteOffline, or DeleteByName.

.PARAMETER AgentName
    Agent name to delete (only used with DeleteByName action).

.PARAMETER PersonalAccessToken
    PAT with "Agent Pools > Read & Manage" scope.

.EXAMPLE
    # List all agents in the Default pool
    .\Manage-BuildAgents.ps1 -Organization myorg -PoolName Default -Action List -PersonalAccessToken $env:ADO_PAT

.EXAMPLE
    # Remove all offline agents
    .\Manage-BuildAgents.ps1 -Organization myorg -PoolName Default -Action DeleteOffline -PersonalAccessToken $env:ADO_PAT
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $PoolName,
    [ValidateSet('List', 'DeleteOffline', 'DeleteByName')]
    [string] $Action = 'List',
    [string] $AgentName,
    [string] $PersonalAccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiParams = @{
    Organization        = $Organization
    PersonalAccessToken = $PersonalAccessToken
}

#region ── Resolve pool ID ────────────────────────────────────────────────────
$pools  = .\Invoke-AzureDevOpsApi.ps1 @apiParams -ApiPath '/_apis/distributedtask/pools?api-version=7.1'
$pool   = $pools.value | Where-Object { $_.name -eq $PoolName }

if (-not $pool) {
    throw "Agent pool '$PoolName' not found in organization '$Organization'."
}

$poolId = $pool.id
Write-Verbose "Pool '$PoolName' has ID $poolId"
#endregion

#region ── Fetch agents ───────────────────────────────────────────────────────
$agents = (.\Invoke-AzureDevOpsApi.ps1 @apiParams `
    -ApiPath "/_apis/distributedtask/pools/$poolId/agents?includeCapabilities=false&api-version=7.1").value
#endregion

switch ($Action) {
    'List' {
        $agents | Select-Object id, name, status, enabled, version,
            @{ N = 'OS'; E = { $_.systemCapabilities.'Agent.OS' } },
            @{ N = 'LastContact'; E = { $_.createdOn } } |
            Format-Table -AutoSize
    }

    'DeleteOffline' {
        $offline = $agents | Where-Object { $_.status -ne 'online' }

        if (-not $offline) {
            Write-Host 'No offline agents found.' -ForegroundColor Green
            return
        }

        foreach ($agent in $offline) {
            if ($PSCmdlet.ShouldProcess($agent.name, "Delete offline agent")) {
                Write-Host "Deleting offline agent '$($agent.name)' (ID: $($agent.id))..." -ForegroundColor Yellow
                .\Invoke-AzureDevOpsApi.ps1 @apiParams `
                    -ApiPath "/_apis/distributedtask/pools/$poolId/agents/$($agent.id)?api-version=7.1" `
                    -Method DELETE | Out-Null
                Write-Host "  Deleted." -ForegroundColor Gray
            }
        }
    }

    'DeleteByName' {
        if (-not $AgentName) { throw "-AgentName is required for DeleteByName action." }

        $agent = $agents | Where-Object { $_.name -eq $AgentName }
        if (-not $agent) { throw "Agent '$AgentName' not found in pool '$PoolName'." }

        if ($PSCmdlet.ShouldProcess($AgentName, "Delete agent")) {
            Write-Host "Deleting agent '$AgentName' (ID: $($agent.id))..." -ForegroundColor Yellow
            .\Invoke-AzureDevOpsApi.ps1 @apiParams `
                -ApiPath "/_apis/distributedtask/pools/$poolId/agents/$($agent.id)?api-version=7.1" `
                -Method DELETE | Out-Null
            Write-Host "Agent '$AgentName' deleted." -ForegroundColor Green
        }
    }
}
