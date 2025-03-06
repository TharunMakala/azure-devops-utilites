// =============================================================================
// main.bicep — Azure DevOps Supporting Infrastructure
// Orchestrates modules for agent pools and artifact storage.
// =============================================================================

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────
@description('Deployment environment (dev, staging, production).')
@allowed(['dev', 'staging', 'production'])
param environment string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Project name prefix applied to all resource names.')
@minLength(2)
@maxLength(10)
param projectName string

@description('Tags applied to all resources.')
param tags object = {
  Project:     projectName
  Environment: environment
  ManagedBy:   'Bicep'
  Repository:  'azure-devops-utilities'
}

@description('Enable self-hosted agent VM Scale Set.')
param deployAgentPool bool = true

@description('Agent VM SKU.')
param agentVmSku string = 'Standard_D2s_v5'

@description('Minimum number of agent VMs.')
@minValue(0)
param agentMinCount int = 0

@description('Maximum number of agent VMs.')
@maxValue(100)
param agentMaxCount int = 10

@description('Admin username for agent VMs.')
param agentAdminUsername string = 'azagent'

@description('Admin password for agent VMs (use Key Vault reference in production).')
@secure()
param agentAdminPassword string

// ── Variables ─────────────────────────────────────────────────────────────────
var resourcePrefix = '${projectName}-${environment}'

// ── Modules ───────────────────────────────────────────────────────────────────

// Artifact storage
module storage './modules/storage.bicep' = {
  name: 'storage-${resourcePrefix}'
  params: {
    storageAccountName: 'st${projectName}${environment}ado'
    location:           location
    tags:               tags
    environment:        environment
  }
}

// Self-hosted agent infrastructure
module agentPool './modules/agent-pool.bicep' = if (deployAgentPool) {
  name: 'agentpool-${resourcePrefix}'
  params: {
    resourcePrefix:   resourcePrefix
    location:         location
    tags:             tags
    vmSku:            agentVmSku
    minCount:         agentMinCount
    maxCount:         agentMaxCount
    adminUsername:    agentAdminUsername
    adminPassword:    agentAdminPassword
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output storageAccountName string = storage.outputs.storageAccountName
output storagePrimaryEndpoint string = storage.outputs.primaryBlobEndpoint
output agentVmssName string = deployAgentPool ? agentPool.outputs.vmssName : 'not-deployed'
