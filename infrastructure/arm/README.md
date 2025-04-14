# ARM Templates

Legacy ARM JSON templates for compatibility with older toolchains or non-Bicep workflows.

> **Recommendation:** Use Bicep templates in `../bicep/` for new deployments.

## Deploy

```bash
az deployment group create \
  --resource-group rg-devops-infra \
  --template-file azuredeploy.json \
  --parameters @azuredeploy.parameters.json
```
