resource "azurerm_container_registry" "main" {
  name                = replace("acr${var.project_name}${var.environment}", "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = var.admin_enabled
  tags                = var.tags

  dynamic "georeplications" {
    for_each = var.sku == "Premium" ? var.georeplications : []
    content {
      location = georeplications.value.location
      tags     = georeplications.value.tags
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_container_registry_webhook" "build_complete" {
  count               = var.sku != "Basic" ? 1 : 0
  name                = "buildComplete"
  registry_name       = azurerm_container_registry.main.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_uri         = "https://placeholder.example.com/webhook"
  actions             = ["push"]
  status              = "disabled"
  scope               = "repo:*"
}
