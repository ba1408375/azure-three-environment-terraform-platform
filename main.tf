#######################################
# Azure VM SSH key
#######################################

resource "tls_private_key" "azure_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "azure_pem" {
  filename        = "${path.module}/azure-key-${var.request_id}.pem"
  content         = tls_private_key.azure_ssh.private_key_pem
  file_permission = "0400"
}

#######################################
# Combined 36-container bootstrap
#######################################

locals {
  core_user_data = {
    for environment in keys(var.environment_instances) : environment => templatefile("${path.module}/userdata.sh", {
      environment_name      = environment
      admin_username        = var.admin_username
      mysql_root_password   = var.mysql_root_password
      mysql_database        = var.mysql_database
      mysql_user            = var.mysql_user
      mysql_password        = var.mysql_password
      mariadb_root_password = var.mariadb_root_password
      mariadb_database      = var.mariadb_database
      mariadb_user          = var.mariadb_user
      mariadb_password      = var.mariadb_password
      postgres_user         = var.postgres_user
      postgres_password     = var.postgres_password
      postgres_database     = var.postgres_database
      mongodb_user          = var.mongodb_user
      mongodb_password      = var.mongodb_password
      jupyter_token         = var.jupyter_token
      webxr_index           = file("${path.module}/webxr/index.html")
    })
  }

  environment_custom_data = {
    for environment in keys(var.environment_instances) : environment => base64encode(join("\n\n", [
      local.core_user_data[environment],
      local.platform_user_data[environment]
    ]))
  }
}

#######################################
# Dev, test, and production Azure VMs
#######################################

resource "azurerm_linux_virtual_machine" "environment" {
  for_each = var.environment_instances

  name                            = each.key
  computer_name                   = "${var.project_name}-${each.key}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = each.value.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.environment[each.key].id]
  custom_data                     = local.environment_custom_data[each.key]
  provision_vm_agent              = true
  patch_assessment_mode           = "AutomaticByPlatform"
  secure_boot_enabled             = true
  vtpm_enabled                    = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.azure_ssh.public_key_openssh
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "${var.project_name}-${each.key}-${local.resource_suffix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = each.value.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  boot_diagnostics {}

  tags = merge(local.common_tags, {
    Name        = each.key
    Environment = each.key
    Stack       = "DevCloud-Multi-Environment"
  })

  depends_on = [
    azurerm_subnet_network_security_group_association.environment
  ]
}
