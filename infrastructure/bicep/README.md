# Bicep Templates

## Structure

```
bicep/
├── main.bicep              # Entry point — orchestrates all modules
├── parameters/
│   ├── dev.json            # Dev environment parameters
│   ├── staging.json        # Staging environment parameters
│   └── production.json     # Production environment parameters
└── modules/
    ├── agent-pool.bicep    # Self-hosted agent infrastructure (VM Scale Set)
    └── storage.bicep       # Storage account for pipeline artifacts and state
```

## Quick Start

```bash
# Create resource group
az group create --name rg-devops-infra --location eastus

# Deploy to dev
az deployment group create \
  --resource-group rg-devops-infra \
  --template-file main.bicep \
  --parameters @parameters/dev.json
```
