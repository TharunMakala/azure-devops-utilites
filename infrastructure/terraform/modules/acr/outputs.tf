output "login_server" { value = azurerm_container_registry.main.login_server }
output "acr_id" { value = azurerm_container_registry.main.id }
output "identity_principal_id" { value = azurerm_container_registry.main.identity[0].principal_id }
