variable "project_name" {
  type        = string
  description = "Name of the project, used in resource naming"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region for resources"
}

variable "cost_center" {
  type        = string
  default     = "engineering"
  description = "Cost center for billing tags"
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "Address space for the virtual network"
}

variable "subnet_prefixes" {
  type = map(object({
    address_prefix                         = string
    service_endpoints                      = optional(list(string), [])
    private_endpoint_network_policies_enabled = optional(bool, true)
  }))
  default = {
    agents = {
      address_prefix    = "10.0.1.0/24"
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    endpoints = {
      address_prefix                         = "10.0.2.0/24"
      private_endpoint_network_policies_enabled = false
    }
    aks = {
      address_prefix    = "10.0.4.0/22"
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    }
  }
}

variable "acr_sku" {
  type        = string
  default     = "Standard"
  description = "SKU tier for Azure Container Registry"
}

variable "acr_georeplications" {
  type = list(object({
    location = string
    tags     = optional(map(string), {})
  }))
  default     = []
  description = "Geo-replication locations for ACR (requires Premium SKU)"
}

variable "keyvault_admin_object_ids" {
  type        = list(string)
  default     = []
  description = "Azure AD object IDs that get admin access to Key Vault"
}
