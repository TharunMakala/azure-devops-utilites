variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "address_space" { type = list(string) }
variable "subnet_prefixes" {
  type = map(object({
    address_prefix                         = string
    service_endpoints                      = optional(list(string), [])
    private_endpoint_network_policies_enabled = optional(bool, true)
  }))
}
variable "tags" { type = map(string) }
