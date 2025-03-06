// =============================================================================
// modules/storage.bicep
// Storage account for pipeline artifacts, Terraform state, and build cache.
// =============================================================================

@description('Storage account name (3-24 lowercase alphanumeric).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Environment name for SKU selection.')
@allowed(['dev', 'staging', 'production'])
param environment string

// Use LRS for dev, ZRS for production
var storageSku = environment == 'production' ? 'Standard_ZRS' : 'Standard_LRS'

// ── Storage Account ───────────────────────────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name:     storageAccountName
  location: location
  tags:     tags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier:              'Hot'
    allowBlobPublicAccess:   false
    allowSharedKeyAccess:    false             // Enforce Entra ID authentication
    minimumTlsVersion:       'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass:        'AzureServices'
      defaultAction: environment == 'production' ? 'Deny' : 'Allow'
    }
    encryption: {
      services: {
        blob: { enabled: true; keyType: 'Account' }
        file: { enabled: true; keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ── Blob Containers ───────────────────────────────────────────────────────────
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-04-01' = {
  parent: storageAccount
  name:   'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days:    environment == 'production' ? 30 : 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days:    environment == 'production' ? 30 : 7
    }
  }
}

resource artifactsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobService
  name:   'artifacts'
  properties: {
    publicAccess: 'None'
  }
}

resource tfstateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobService
  name:   'tfstate'
  properties: {
    publicAccess: 'None'
  }
}

resource cacheContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobService
  name:   'pipeline-cache'
  properties: {
    publicAccess: 'None'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output storageAccountName string    = storageAccount.name
output storageAccountId string      = storageAccount.id
output primaryBlobEndpoint string   = storageAccount.properties.primaryEndpoints.blob
