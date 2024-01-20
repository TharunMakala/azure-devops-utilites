# Azure DevOps Utilities

A professional toolkit for Azure DevOps engineers — reusable pipeline templates, automation scripts, Infrastructure as Code, and operational documentation.

## Repository Structure

```
azure-devops-utilities/
├── pipelines/                  # Azure Pipelines YAML definitions
│   ├── templates/              # Reusable step templates (build, test, deploy)
│   ├── ci/                     # CI pipelines for .NET, Node.js, Python
│   └── cd/                     # CD pipelines for App Service and AKS
│
├── scripts/                    # Automation scripts
│   ├── powershell/             # PowerShell scripts (cross-platform, pwsh 7+)
│   └── bash/                   # Bash scripts (Linux / macOS / Cloud Shell)
│
├── infrastructure/             # Infrastructure as Code
│   ├── bicep/                  # Bicep templates (recommended)
│   └── arm/                    # ARM JSON templates (legacy)
│
├── policies/                   # Branch policies and permission matrices
├── docs/                       # Guides and reference documentation
└── tools/                      # Python CLI utility
```

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_ORG/azure-devops-utilities.git
cd azure-devops-utilities

# 2. Bootstrap your machine (Ubuntu/Debian)
sudo ./scripts/bash/setup-environment.sh

# 3. Authenticate
az login
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG project=YOUR_PROJECT
export ADO_PAT="your-personal-access-token"
```

See [docs/getting-started.md](docs/getting-started.md) for a full walkthrough.

---

## Pipelines

### CI Templates

| Pipeline | Stack | Features |
|----------|-------|----------|
| [`ci/dotnet-ci.yml`](pipelines/ci/dotnet-ci.yml) | .NET 8 | Build, test, coverage, SonarCloud, NuGet audit |
| [`ci/node-ci.yml`](pipelines/ci/node-ci.yml) | Node.js 20 | Lint, build, jest coverage, npm audit |
| [`ci/python-ci.yml`](pipelines/ci/python-ci.yml) | Python 3.12 | Ruff, Black, pytest, wheel packaging |

### CD Pipelines

| Pipeline | Target | Strategy |
|----------|--------|----------|
| [`cd/deploy-to-azure.yml`](pipelines/cd/deploy-to-azure.yml) | Azure App Service | Rolling, with slot swap rollback |
| [`cd/deploy-to-kubernetes.yml`](pipelines/cd/deploy-to-kubernetes.yml) | AKS | Canary (10% → 50% → 100%) |

### Reusable Templates

| Template | Purpose |
|----------|---------|
| [`templates/build-template.yml`](pipelines/templates/build-template.yml) | .NET restore, build, publish |
| [`templates/test-template.yml`](pipelines/templates/test-template.yml) | Run tests, publish results and coverage |
| [`templates/deploy-template.yml`](pipelines/templates/deploy-template.yml) | Deploy to App Service or AKS |

---

## Scripts

### PowerShell

| Script | Description |
|--------|-------------|
| [`Invoke-AzureDevOpsApi.ps1`](scripts/powershell/Invoke-AzureDevOpsApi.ps1) | Generic REST API helper with auth and retry |
| [`Create-AzureDevOpsProject.ps1`](scripts/powershell/Create-AzureDevOpsProject.ps1) | Create a new project and wait for provisioning |
| [`Manage-BuildAgents.ps1`](scripts/powershell/Manage-BuildAgents.ps1) | List, and remove offline or named agents |
| [`Export-PipelineDefinitions.ps1`](scripts/powershell/Export-PipelineDefinitions.ps1) | Export all pipeline definitions to YAML/JSON |
| [`Set-VariableGroups.ps1`](scripts/powershell/Set-VariableGroups.ps1) | Create/update variable groups (plain or Key Vault) |

### Bash

| Script | Description |
|--------|-------------|
| [`setup-environment.sh`](scripts/bash/setup-environment.sh) | Bootstrap a Linux machine with all ADO tools |
| [`create-service-connection.sh`](scripts/bash/create-service-connection.sh) | Create ARM service connections via Azure CLI |
| [`manage-agents.sh`](scripts/bash/manage-agents.sh) | Install, start, stop, and remove self-hosted agents |
| [`export-repos.sh`](scripts/bash/export-repos.sh) | Clone or mirror all repositories in a project |

---

## Infrastructure

Bicep and ARM templates to provision Azure DevOps supporting resources:

- **Storage account** — artifacts, Terraform state, pipeline cache
- **VM Scale Set** — self-hosted agent pool with auto-scaling

```bash
# Deploy to dev
az deployment group create \
    --resource-group rg-devops-infra \
    --template-file infrastructure/bicep/main.bicep \
    --parameters @infrastructure/bicep/parameters/dev.json
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Prerequisites, auth, and first pipeline |
| [Pipeline Best Practices](docs/pipeline-best-practices.md) | Security, performance, and maintainability patterns |
| [Agent Setup Guide](docs/agent-setup.md) | VMSS pools, single VMs, and Docker agents |
| [Troubleshooting](docs/troubleshooting.md) | Common problems and solutions |

---

## Tools (Python CLI)

```bash
cd tools && pip install -r requirements.txt

# List projects
python az_devops_helper.py projects --org myorg

# Show last 20 pipeline runs
python az_devops_helper.py runs --org myorg --project MyProject --limit 20

# Export active work items to CSV
python az_devops_helper.py workitems --org myorg --project MyProject --output items.csv
```

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow existing naming conventions and add a README to any new directory.
3. Test scripts locally before submitting a pull request.
4. Open a pull request with a clear description of changes.

## License

[MIT License](LICENSE)
