output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "resource_group_id" {
  value = azurerm_resource_group.main.id
}

output "vnet_id" {
  value = module.vnet.vnet_id
}

output "vnet_name" {
  value = module.vnet.vnet_name
}

output "subnet_ids" {
  value = module.vnet.subnet_ids
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "acr_id" {
  value = module.acr.acr_id
}

output "keyvault_id" {
  value = module.keyvault.keyvault_id
}

output "keyvault_uri" {
  value = module.keyvault.keyvault_uri
}
