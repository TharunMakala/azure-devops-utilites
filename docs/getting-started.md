# Getting Started

## Prerequisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Azure CLI | 2.58+ | [docs.microsoft.com](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Azure DevOps CLI extension | latest | `az extension add --name azure-devops` |
| PowerShell | 7.4+ | [github.com/PowerShell](https://github.com/PowerShell/PowerShell/releases) |
| Git | 2.40+ | [git-scm.com](https://git-scm.com/downloads) |

Or run the bootstrap script (Ubuntu/Debian):

```bash
sudo ./scripts/bash/setup-environment.sh
```

## 1. Authenticate

```bash
# Azure CLI
az login
az devops configure --defaults \
    organization=https://dev.azure.com/YOUR_ORG \
    project=YOUR_PROJECT

# Set a PAT for PowerShell scripts
export ADO_PAT="your-personal-access-token"
```

**Create a PAT** at `https://dev.azure.com/YOUR_ORG/_usersSettings/tokens` with these scopes:

| Scope | Access |
|-------|--------|
| Agent Pools | Read & Manage |
| Build | Read & Execute |
| Project and Team | Read & Write |
| Release | Read, write, execute & manage |
| Service Connections | Read, query & manage |
| Variable Groups | Read, create & manage |

## 2. Create Your First Project

```powershell
.\scripts\powershell\Create-AzureDevOpsProject.ps1 `
    -Organization "myorg" `
    -ProjectName  "MyFirstProject" `
    -Description  "Created with azure-devops-utilities" `
    -PersonalAccessToken $env:ADO_PAT
```

## 3. Set Up a Service Connection

```bash
./scripts/bash/create-service-connection.sh \
    --org          https://dev.azure.com/myorg \
    --project      MyFirstProject \
    --name         "Azure Subscription" \
    --subscription YOUR_SUBSCRIPTION_ID \
    --tenant       YOUR_TENANT_ID
```

## 4. Create a Variable Group

```powershell
$vars = @{
    APP_ENV     = @{ value = "production"; isSecret = $false }
    API_BASE_URL = @{ value = "https://api.example.com"; isSecret = $false }
}

.\scripts\powershell\Set-VariableGroups.ps1 `
    -Organization "myorg" `
    -Project      "MyFirstProject" `
    -GroupName    "MyApp-Vars" `
    -Variables    $vars `
    -PersonalAccessToken $env:ADO_PAT
```

## 5. Register Your First Pipeline

Copy a CI pipeline template into your application repository:

```bash
cp pipelines/ci/dotnet-ci.yml /path/to/your/repo/azure-pipelines.yml
```

Then register it in Azure DevOps:

```bash
az pipelines create \
    --name  "CI - Build & Test" \
    --yml-path azure-pipelines.yml \
    --repository YOUR_REPO_NAME \
    --repository-type tfsgit \
    --branch main
```

## 6. Deploy Infrastructure

```bash
az group create --name rg-devops-infra --location eastus

az deployment group create \
    --resource-group rg-devops-infra \
    --template-file infrastructure/bicep/main.bicep \
    --parameters @infrastructure/bicep/parameters/dev.json \
    --parameters agentAdminPassword="SECURE_PASSWORD"
```

## Next Steps

- Read [pipeline-best-practices.md](pipeline-best-practices.md) before writing production pipelines.
- Follow [agent-setup.md](agent-setup.md) if you need self-hosted agents.
- Check [troubleshooting.md](troubleshooting.md) if something goes wrong.
