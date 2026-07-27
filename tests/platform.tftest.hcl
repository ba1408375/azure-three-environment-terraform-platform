mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg"
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/networkSecurityGroups/mock-nsg"
    }
  }

  mock_resource "azurerm_network_interface" {
    defaults = {
      id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/networkInterfaces/mock-nic"
      private_ip_address = "10.42.10.4"
    }
  }

  mock_resource "azurerm_service_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Web/serverFarms/mock-plan"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-logs"
    }
  }

  mock_resource "azurerm_linux_function_app" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Web/sites/mock-function"
      default_hostname = "devcloud-faas.example.azurewebsites.net"
    }
  }

  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/publicIPAddresses/mock-pip"
      ip_address = "203.0.113.10"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mockstorage"
      primary_access_key = "bW9jay1henVyZS1zdG9yYWdlLWFjY2Vzcy1rZXktZm9yLXRlc3Rpbmctb25seQ=="
    }
  }

  mock_resource "azurerm_application_insights" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Insights/components/mock-insights"
      connection_string   = "InstrumentationKey=00000000-0000-0000-0000-000000000000"
      instrumentation_key = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Compute/virtualMachines/mock-vm"
    }
  }
}

mock_provider "local" {}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "MockNiFiPassword123456789"
    }
  }

  mock_resource "random_string" {
    defaults = {
      result = "mock1234"
    }
  }
}

run "three_environment_azure_mock_apply" {
  command = apply

  variables {
    azure_subscription_id = "00000000-0000-0000-0000-000000000000"
    request_id            = "validation"

    mysql_root_password = "ValidationRoot123"
    mysql_database      = "validation"
    mysql_user          = "validation"
    mysql_password      = "ValidationUser123"

    mariadb_root_password = "ValidationRoot123"
    mariadb_database      = "validation"
    mariadb_user          = "validation"
    mariadb_password      = "ValidationUser123"

    postgres_user     = "validation"
    postgres_password = "ValidationUser123"
    postgres_database = "validation"

    mongodb_user     = "validation"
    mongodb_password = "ValidationUser123"
    jupyter_token    = "ValidationToken123"
  }

  assert {
    condition     = toset(keys(azurerm_linux_virtual_machine.environment)) == toset(["dev", "test", "production"])
    error_message = "Terraform must create exactly the dev, test, and production Azure VMs."
  }

  assert {
    condition = (
      azurerm_linux_virtual_machine.environment["dev"].size == "Standard_D8s_v5" &&
      azurerm_linux_virtual_machine.environment["test"].size == "Standard_D8s_v5" &&
      azurerm_linux_virtual_machine.environment["production"].size == "Standard_D16s_v5"
    )
    error_message = "The Azure environments must use the tested default VM sizes."
  }

  assert {
    condition = alltrue([
      for environment, vm in azurerm_linux_virtual_machine.environment :
      vm.name == environment &&
      vm.tags.Environment == environment &&
      vm.identity[0].type == "SystemAssigned"
    ])
    error_message = "Every Azure VM must be named, tagged, and assigned an identity for its environment."
  }

  assert {
    condition = alltrue([
      for vm in values(azurerm_linux_virtual_machine.environment) :
      vm.os_disk[0].storage_account_type == "Premium_LRS" &&
      vm.secure_boot_enabled &&
      vm.vtpm_enabled
    ])
    error_message = "Every Azure VM must use a Premium OS disk, Secure Boot, and vTPM."
  }

  assert {
    condition = alltrue([
      for payload in values(local.environment_custom_data) :
      nonsensitive(length(base64decode(payload))) <= 65535
    ])
    error_message = "Azure custom data must remain within the 64-KB API limit."
  }

  assert {
    condition = alltrue([
      for payload in values(local.environment_custom_data) :
      length(regexall("container_name:", nonsensitive(base64decode(payload)))) == 36
    ])
    error_message = "Every environment bootstrap must contain all 36 Docker containers."
  }

  assert {
    condition = alltrue([
      for payload in values(local.environment_custom_data) :
      strcontains(
        nonsensitive(base64decode(payload)),
        "https://devcloud-faas.example.azurewebsites.net/api/faas"
      )
    ])
    error_message = "Every Kong configuration must target the shared Azure Function endpoint."
  }

  assert {
    condition = (
      length(azurerm_subnet.environment) == 3 &&
      length(azurerm_network_interface.environment) == 3 &&
      length(azurerm_public_ip.environment) == 3 &&
      length(azurerm_subnet_network_security_group_association.environment) == 3
    )
    error_message = "Every environment must have one subnet, NSG association, NIC, and static public IP."
  }

  assert {
    condition = alltrue([
      for public_ip in values(azurerm_public_ip.environment) :
      public_ip.sku == "Standard" &&
      public_ip.allocation_method == "Static"
    ])
    error_message = "Every environment must use a static Standard Azure public IP."
  }

  assert {
    condition = alltrue([
      for vm in values(azurerm_linux_virtual_machine.environment) :
      length(vm.network_interface_ids) == 1
    ])
    error_message = "Every Azure VM must have exactly one network interface."
  }

  assert {
    condition     = length(azurerm_network_security_rule.ssh) == 0
    error_message = "Public SSH must remain disabled unless trusted admin CIDRs are supplied."
  }

  assert {
    condition = (
      length(azurerm_network_security_rule.public_tcp) == 0 &&
      length(azurerm_network_security_rule.public_udp) == 0
    )
    error_message = "Public service access must remain disabled until trusted CIDRs are supplied."
  }

  assert {
    condition = alltrue([
      for port in local.private_tcp_ports :
      !contains(local.public_tcp_ports, port)
    ])
    error_message = "Database and administration ports must not appear in the public TCP rule."
  }

  assert {
    condition     = length(random_password.platform_nifi) == 3
    error_message = "NiFi must have a separate generated password in each Azure environment."
  }

  assert {
    condition = (
      azurerm_linux_function_app.faas.functions_extension_version == "~4" &&
      azurerm_linux_function_app.faas.site_config[0].application_stack[0].python_version == "3.12" &&
      azurerm_linux_function_app.faas.https_only &&
      azurerm_linux_function_app.faas.site_config[0].minimum_tls_version == "1.2" &&
      azurerm_linux_function_app.faas.identity[0].type == "SystemAssigned" &&
      azurerm_linux_function_app.faas.app_settings["FUNCTIONS_WORKER_RUNTIME"] == "python"
    )
    error_message = "The shared FaaS endpoint must use Azure Functions v4, Python 3.12, HTTPS/TLS 1.2, and managed identity."
  }

  assert {
    condition = (
      azurerm_service_plan.faas.os_type == "Linux" &&
      azurerm_service_plan.faas.sku_name == "B1" &&
      azurerm_storage_account.faas.account_tier == "Standard" &&
      azurerm_storage_account.faas.account_replication_type == "LRS" &&
      azurerm_storage_account.faas.min_tls_version == "TLS1_2" &&
      azurerm_storage_account.faas.https_traffic_only_enabled
    )
    error_message = "The Function App must use the expected Linux plan and secure Standard LRS storage."
  }

  assert {
    condition = (
      toset(keys(local.environment_service_urls)) == toset(["dev", "test", "production"]) &&
      toset(keys(local.environment_run_commands)) == toset(["dev", "test", "production"]) &&
      toset(keys(local.environment_nifi_ssh_tunnels)) == toset(["dev", "test", "production"])
    )
    error_message = "All environment output maps must contain exactly dev, test, and production."
  }
}
