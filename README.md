# Azure DevOps Utilities

A comprehensive toolkit for Azure DevOps engineers — reusable pipeline templates, automation scripts, Infrastructure as Code, monitoring tools, and operational documentation.

## Repository Structure

```
azure-devops-utilities/
├── pipelines/                  # Azure Pipelines YAML definitions
│   ├── templates/              # Reusable step templates (build, test, deploy)
│   ├── ci/                     # CI pipelines (.NET, Node.js, Python, security, load testing)
│   └── cd/                     # CD pipelines (App Service, AKS, database migrations)
│
├── scripts/                    # Automation scripts
│   ├── powershell/             # PowerShell scripts (cross-platform, pwsh 7+)
│   └── bash/                   # Bash scripts (Linux / macOS / Cloud Shell)
│
├── infrastructure/             # Infrastructure as Code
│   ├── bicep/                  # Bicep templates (recommended)
│   ├── terraform/              # Terraform modules (VNet, ACR, Key Vault)
│   └── arm/                    # ARM JSON templates (legacy)
│
├── docker/                     # Docker configurations
│   ├── agent/                  # Self-hosted agent container with Docker Compose
│   └── devcontainer/           # VS Code dev container
│
├── helm/                       # Helm charts
│   └── azure-agent/            # Kubernetes agent deployment with HPA
│
├── tools/                      # CLI tools and utilities
│   ├── az_devops_helper.py     # Python CLI for DevOps operations
│   ├── pipeline-monitor/       # Go CLI for real-time pipeline monitoring
│   ├── webhook-server/         # FastAPI webhook event router
│   ├── compliance-checker/     # Project security audit tool
│   ├── config-manager/         # Multi-environment config management
│   └── dashboard/              # Project metrics and reporting
│
├── policies/                   # Branch policies and permission matrices
├── tests/                      # Unit and integration tests
├── docs/                       # Guides and reference documentation
└── pytest.ini                  # Test configuration
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
export AZDO_PAT="your-personal-access-token"
```

See [docs/getting-started.md](docs/getting-started.md) for a full walkthrough.

---

## Pipelines

### CI Pipelines

| Pipeline | Stack | Features |
|----------|-------|----------|
| [`ci/dotnet-ci.yml`](pipelines/ci/dotnet-ci.yml) | .NET 8 | Build, test, coverage, SonarCloud, NuGet audit |
| [`ci/node-ci.yml`](pipelines/ci/node-ci.yml) | Node.js 20 | Lint, build, jest coverage, npm audit |
| [`ci/python-ci.yml`](pipelines/ci/python-ci.yml) | Python 3.12 | Ruff, Black, pytest, wheel packaging |
| [`ci/security-scan.yml`](pipelines/ci/security-scan.yml) | Multi-tool | Semgrep SAST, Bandit, Gitleaks, Trivy, Checkov |
| [`ci/load-test.yml`](pipelines/ci/load-test.yml) | k6 | Configurable VUs, thresholds, P95/P99 metrics |

### CD Pipelines

| Pipeline | Target | Strategy |
|----------|--------|----------|
| [`cd/deploy-to-azure.yml`](pipelines/cd/deploy-to-azure.yml) | Azure App Service | Rolling, with slot swap rollback |
| [`cd/deploy-to-kubernetes.yml`](pipelines/cd/deploy-to-kubernetes.yml) | AKS | Canary (10% → 50% → 100%) |
| [`cd/database-migration.yml`](pipelines/cd/database-migration.yml) | SQL Server | Flyway with dry-run, backup, and verification |

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
| [`Get-AzureCostReport.ps1`](scripts/powershell/Get-AzureCostReport.ps1) | Azure cost analysis with budget alerts and trends |

### Bash

| Script | Description |
|--------|-------------|
| [`setup-environment.sh`](scripts/bash/setup-environment.sh) | Bootstrap a Linux machine with all ADO tools |
| [`create-service-connection.sh`](scripts/bash/create-service-connection.sh) | Create ARM service connections via Azure CLI |
| [`manage-agents.sh`](scripts/bash/manage-agents.sh) | Install, start, stop, and remove self-hosted agents |
| [`export-repos.sh`](scripts/bash/export-repos.sh) | Clone or mirror all repositories in a project |

---

## Infrastructure

### Bicep (Recommended)

Storage accounts, VM Scale Set agent pools — see [`infrastructure/bicep/`](infrastructure/bicep/).

### Terraform

Modular configuration with VNet, ACR, and Key Vault modules:

```bash
cd infrastructure/terraform
terraform init
terraform plan -var-file="environments/dev/terraform.tfvars"
terraform apply -var-file="environments/dev/terraform.tfvars"
```

See [`infrastructure/terraform/README.md`](infrastructure/terraform/README.md) for details.

---

## Docker & Kubernetes

### Self-Hosted Agent Container

```bash
cd docker/agent
docker compose up -d                    # Start 2 agents
docker compose up -d --scale azure-agent=5  # Scale to 5
```

### Helm Chart (AKS)

```bash
helm install azure-agent helm/azure-agent \
  --set azureDevOps.orgUrl="https://dev.azure.com/myorg" \
  --set azureDevOps.pat="$AZDO_PAT" \
  --namespace azure-devops --create-namespace
```

Features: HPA auto-scaling, persistent volumes, Docker-in-Docker sidecar, PDB.

---

## Tools

| Tool | Language | Description |
|------|----------|-------------|
| [`az_devops_helper.py`](tools/az_devops_helper.py) | Python | CLI for projects, pipelines, and work items |
| [`pipeline-monitor`](tools/pipeline-monitor/) | Go | Real-time pipeline monitoring with Slack alerts |
| [`webhook-server`](tools/webhook-server/) | Python | Event router for Slack/Teams notifications |
| [`compliance-checker`](tools/compliance-checker/) | Python | Security and policy audit tool |
| [`config-manager`](tools/config-manager/) | Python | Multi-env config validation and drift detection |
| [`dashboard`](tools/dashboard/) | Python | Metrics dashboard (terminal, HTML, JSON) |

### Quick Examples

```bash
# Monitor pipelines in real-time
cd tools/pipeline-monitor && go build && ./pipeline-monitor watch

# Run compliance audit
python tools/compliance-checker/checker.py --fail-on-critical

# Generate HTML dashboard
python tools/dashboard/dashboard.py html --output report.html

# Detect config drift
python tools/config-manager/config_manager.py drift --base staging --target production
```

---

## Testing

```bash
pip install -r tests/requirements.txt
pytest                          # Run all tests
pytest tests/unit/              # Unit tests only
pytest tests/integration/       # Integration tests
pytest --cov=tools              # With coverage
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Prerequisites, auth, and first pipeline |
| [Pipeline Best Practices](docs/pipeline-best-practices.md) | Security, performance, and maintainability patterns |
| [Agent Setup Guide](docs/agent-setup.md) | VMSS pools, single VMs, Docker, and Kubernetes agents |
| [Troubleshooting](docs/troubleshooting.md) | Common problems and solutions |

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow existing naming conventions and add a README to any new directory.
3. Run `pytest` to ensure tests pass before submitting.
4. Open a pull request with a clear description of changes.

## License

[MIT License](LICENSE)
