# Scripts

Utility scripts for Azure DevOps administration and automation.

## Directory Structure

```
scripts/
├── powershell/     # PowerShell scripts (Windows & cross-platform via pwsh)
└── bash/           # Bash scripts (Linux / macOS / Azure Cloud Shell)
```

## Prerequisites

### PowerShell Scripts

```powershell
# Install required modules
Install-Module -Name Az -Scope CurrentUser -Force
Install-Module -Name VSTeam -Scope CurrentUser -Force

# Authenticate
Connect-AzAccount
```

### Bash Scripts

```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Azure DevOps extension
az extension add --name azure-devops

# Authenticate
az login
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG
```

## Script Inventory

### PowerShell

| Script | Description |
|--------|-------------|
| `Create-AzureDevOpsProject.ps1` | Create a new ADO project with default settings |
| `Manage-BuildAgents.ps1` | Register, unregister, and list self-hosted agents |
| `Export-PipelineDefinitions.ps1` | Export pipeline YAML definitions from an organization |
| `Set-VariableGroups.ps1` | Create or update variable groups and link to Key Vault |
| `Invoke-AzureDevOpsApi.ps1` | Generic helper to call the Azure DevOps REST API |

### Bash

| Script | Description |
|--------|-------------|
| `create-service-connection.sh` | Create Azure Resource Manager service connections |
| `manage-agents.sh` | Install and configure self-hosted build agents on Linux |
| `export-repos.sh` | Clone and mirror all repositories in an ADO project |
| `setup-environment.sh` | Bootstrap a fresh machine with all ADO tools |

## Usage

All scripts support `-Help` / `--help` flags for detailed usage information.
