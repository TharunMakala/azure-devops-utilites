# Terraform Infrastructure

Modular Terraform configuration for provisioning Azure resources used by the DevOps utilities toolkit.

## Modules

| Module | Description |
|--------|-------------|
| `vnet` | Virtual network with subnets, NSGs, and service endpoints |
| `acr` | Azure Container Registry with optional geo-replication |
| `keyvault` | Key Vault with RBAC, diagnostics, and purge protection |

## Usage

```bash
cd infrastructure/terraform
terraform init -backend-config="environments/dev/backend.hcl"
terraform plan -var-file="environments/dev/terraform.tfvars"
terraform apply -var-file="environments/dev/terraform.tfvars"
```

## Environments

Each environment has its own `terraform.tfvars` in `environments/<env>/`:
- **dev**: Basic SKUs, minimal scaling
- **staging**: Standard SKUs, moderate scaling
- **production**: Premium SKUs, geo-replication, full HA
