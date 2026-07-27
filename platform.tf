#######################################
# Added-service rendering
#######################################

locals {
  storage_name_prefix = substr(
    lower(replace("${var.project_name}${local.compact_suffix}", "/[^0-9a-z]/", "")),
    0,
    15
  )

  function_app_name = substr(
    "${var.project_name}-faas-${local.resource_suffix}-${random_string.azure_resource_suffix.result}",
    0,
    60
  )

  function_url = "https://${azurerm_linux_function_app.faas.default_hostname}/api/faas"

  platform_compose = {
    for environment in keys(var.environment_instances) : environment => templatefile("${path.module}/platform/docker-compose.yml.tftpl", {
      images        = var.platform_images
      nifi_username = var.platform_nifi_username
      nifi_password = random_password.platform_nifi[environment].result
    })
  }

  platform_kong_config = templatefile("${path.module}/platform/kong.yml.tftpl", {
    faas_url = local.function_url
  })

  platform_user_data = {
    for environment in keys(var.environment_instances) : environment => templatefile("${path.module}/platform_userdata.sh", {
      ar_index         = file("${path.module}/platform/ar/index.html")
      vr_index         = file("${path.module}/platform/vr/index.html")
      kong_config      = local.platform_kong_config
      compose_config   = local.platform_compose[environment]
      environment_name = environment
      admin_username   = var.admin_username
    })
  }
}

resource "random_password" "platform_nifi" {
  for_each = var.environment_instances

  length      = 24
  special     = false
  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
}

#######################################
# Azure Function package
#######################################

resource "random_string" "azure_resource_suffix" {
  length  = 8
  upper   = false
  special = false
}

data "archive_file" "faas" {
  type             = "zip"
  source_dir       = "${path.module}/faas"
  output_file_mode = "0666"
  output_path      = "${path.module}/faas/function_app.zip"
  excludes         = ["function_app.zip", "lambda_function.zip", "__pycache__", ".python_packages"]
}

#######################################
# Azure Functions infrastructure
#######################################

resource "azurerm_storage_account" "faas" {
  name = substr(
    "st${local.storage_name_prefix}${random_string.azure_resource_suffix.result}",
    0,
    24
  )

  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  tags                            = local.common_tags
}

resource "azurerm_service_plan" "faas" {
  name                = "${var.project_name}-faas-${local.resource_suffix}-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_plan_sku
  tags                = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-${local.resource_suffix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "faas" {
  name                = "${var.project_name}-faas-${local.resource_suffix}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

resource "azurerm_linux_function_app" "faas" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.faas.id

  storage_account_name       = azurerm_storage_account.faas.name
  storage_account_access_key = azurerm_storage_account.faas.primary_access_key

  functions_extension_version   = "~4"
  https_only                    = true
  public_network_access_enabled = true
  zip_deploy_file               = data.archive_file.faas.output_path

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    FUNCTION_PACKAGE_SHA256        = data.archive_file.faas.output_base64sha256
  }

  site_config {
    always_on                              = true
    ftps_state                             = "Disabled"
    http2_enabled                          = true
    minimum_tls_version                    = "1.2"
    scm_minimum_tls_version                = "1.2"
    application_insights_connection_string = azurerm_application_insights.faas.connection_string
    application_insights_key               = azurerm_application_insights.faas.instrumentation_key

    application_stack {
      python_version = var.function_python_version
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.common_tags, {
    Service = "FaaS"
  })
}
