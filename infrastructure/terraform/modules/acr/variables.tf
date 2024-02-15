variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "sku" { type = string }
variable "admin_enabled" { type = bool }
variable "georeplications" {
  type = list(object({
    location = string
    tags     = optional(map(string), {})
  }))
  default = []
}
variable "tags" { type = map(string) }
