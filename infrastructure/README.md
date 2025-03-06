# Infrastructure as Code

Infrastructure templates for Azure DevOps supporting resources.

## Directory Structure

```
infrastructure/
├── bicep/      # Azure Bicep templates (recommended for new deployments)
└── arm/        # ARM JSON templates (legacy / interop)
```

## Bicep vs ARM

Prefer Bicep for all new infrastructure. Bicep compiles to ARM JSON and offers:
- Cleaner, more readable syntax
- Type safety and IDE support
- Modular structure with `module` references
- First-class support for what-if deployments

## Deploying

### Bicep

```bash
# Preview changes (what-if)
az deployment group what-if \
  --resource-group rg-devops-infra \
  --template-file infrastructure/bicep/main.bicep \
  --parameters @infrastructure/bicep/parameters/dev.json

# Deploy
az deployment group create \
  --resource-group rg-devops-infra \
  --template-file infrastructure/bicep/main.bicep \
  --parameters @infrastructure/bicep/parameters/dev.json
```

### ARM

```bash
az deployment group create \
  --resource-group rg-devops-infra \
  --template-file infrastructure/arm/azuredeploy.json \
  --parameters @infrastructure/arm/azuredeploy.parameters.json
```

## References

- [Bicep documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [ARM template reference](https://learn.microsoft.com/en-us/azure/templates/)
