# Bash Scripts

All scripts require the Azure CLI with the `azure-devops` extension.

```bash
az extension add --name azure-devops
az login
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG project=YOUR_PROJECT
```

Make scripts executable before running:

```bash
chmod +x scripts/bash/*.sh
```
