# CD Pipelines

Multi-stage Continuous Deployment pipelines with approval gates.

| File | Target | Environments |
|------|--------|--------------|
| `deploy-to-azure.yml` | Azure App Service | dev → staging → production |
| `deploy-to-kubernetes.yml` | Azure Kubernetes Service | dev → staging → production |

## Prerequisites

- Service connections configured in **Project Settings > Service connections**
- Environments created in **Pipelines > Environments** with approval checks on `staging` and `production`
- Variable groups created and linked to the pipeline

## Environment Approval Gates

Configure manual approval checks on the `staging` and `production` environments in Azure DevOps to require human sign-off before deployment proceeds.
