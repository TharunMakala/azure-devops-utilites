// =============================================================================
// modules/agent-pool.bicep
// VM Scale Set for Azure Pipelines self-hosted agents (VMSS agent pool).
// Compatible with Azure DevOps VMSS Agent Pools feature.
// =============================================================================

@description('Resource name prefix (e.g. myproject-dev).')
param resourcePrefix string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('VM SKU for agents.')
param vmSku string = 'Standard_D2s_v5'

@description('Minimum VM count (0 = scale to zero when idle).')
@minValue(0)
param minCount int = 0

@description('Maximum VM count.')
@minValue(1)
@maxValue(100)
param maxCount int = 10

@description('Agent VM admin username.')
param adminUsername string

@description('Agent VM admin password.')
@secure()
param adminPassword string

@description('OS disk size in GB.')
param osDiskSizeGB int = 128

// ── Virtual Network ───────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name:     '${resourcePrefix}-vnet'
  location: location
  tags:     tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'agents'
        properties: {
          addressPrefix:                     '10.0.1.0/24'
          privateEndpointNetworkPolicies:    'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ── VM Scale Set ──────────────────────────────────────────────────────────────
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name:     '${resourcePrefix}-agents'
  location: location
  tags:     tags
  sku: {
    name:     vmSku
    tier:     'Standard'
    capacity: minCount
  }
  properties: {
    overprovision: false               // ADO manages provisioning, not Azure
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: 'canonical'
          offer:     '0001-com-ubuntu-server-jammy'
          sku:       '22_04-lts-gen2'
          version:   'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching:      'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: osDiskSizeGB
        }
      }
      osProfile: {
        computerNamePrefix: 'agent'
        adminUsername:      adminUsername
        adminPassword:      adminPassword
        linuxConfiguration: {
          disablePasswordAuthentication: false
          provisionVMAgent:              true
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${resourcePrefix}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: '${vnet.id}/subnets/agents'
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ── Autoscale Settings ────────────────────────────────────────────────────────
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name:     '${resourcePrefix}-autoscale'
  location: location
  tags:     tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'default'
        capacity: {
          minimum: string(minCount)
          maximum: string(maxCount)
          default: string(minCount)
        }
        rules: []   // Scaling is managed by Azure DevOps VMSS pool feature
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output vmssName string = vmss.name
output vmssId string   = vmss.id
output vnetId string   = vnet.id
