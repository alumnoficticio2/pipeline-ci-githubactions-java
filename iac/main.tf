locals {
  # ACR name: solo letras/números y único globalmente
  acr_name = "${var.prefix}${var.suffix}${var.environment}"
  rg_name  = "${var.prefix}-${var.suffix}-${var.environment}-rg"
  app_name = "${var.prefix}-${var.suffix}-${var.environment}-app"
  cae_name = "${var.prefix}-${var.suffix}-${var.environment}-cae"
  law_name = "${var.prefix}-${var.suffix}-${var.environment}-law"
  id_name  = "${var.prefix}-${var.suffix}-${var.environment}-id"
}

resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = local.law_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
}

resource "azurerm_container_app_environment" "cae" {
  name                       = local.cae_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

resource "azurerm_user_assigned_identity" "uai" {
  name                = local.id_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Permiso para extraer imágenes del ACR (AcrPull) usando Managed Identity
resource "azurerm_role_assignment" "acrpull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.uai.principal_id
}

# Imagen: se construirá y subirá como: <login_server>/hola:<image_tag>
locals {
  image_name = "${azurerm_container_registry.acr.login_server}/hola:${var.image_tag}"
}

resource "azurerm_container_app" "app" {
  name                         = local.app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uai.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.uai.id
  }

  template {
    container {
      name   = "hola"
      image  = local.image_name
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.container_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
