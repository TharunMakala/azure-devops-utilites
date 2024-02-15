variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "tenant_id" { type = string }
variable "admin_object_ids" { type = list(string) }
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}
variable "tags" { type = map(string) }
