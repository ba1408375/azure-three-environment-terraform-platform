#######################################
# Azure resource naming and tags
#######################################

locals {
  resource_suffix = substr(
    trim(lower(replace(var.request_id, "/[^0-9A-Za-z-]/", "-")), "-"),
    0,
    24
  )

  compact_suffix = substr(
    lower(replace(var.request_id, "/[^0-9A-Za-z]/", "")),
    0,
    12
  )

  common_tags = merge(var.common_tags, {
    ManagedBy = "Terraform"
    Project   = var.project_name
    RequestId = var.request_id
    Cloud     = "Azure"
  })

  public_tcp_ports = [
    "1883",
    "1935",
    "3000",
    "5678",
    "8000",
    "8080-8083",
    "8085",
    "8090-8093",
    "8501",
    "8554",
    "8889",
    "8891"
  ]

  private_tcp_ports = [
    "3306",
    "3307",
    "5432",
    "6379",
    "8443",
    "8545",
    "8888",
    "9000",
    "18083",
    "27017"
  ]

  public_udp_ports = [
    "8000-8001",
    "8189",
    "8890"
  ]
}

#######################################
# Resource group and virtual network
#######################################

resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${local.resource_suffix}-rg"
  location = var.azure_location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-${local.resource_suffix}-vnet"
  address_space       = ["10.42.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "environment" {
  for_each = var.environment_instances

  name                 = each.key
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.subnet_cidr]
}

#######################################
# Network security
#######################################

resource "azurerm_network_security_group" "services" {
  name                = "${var.project_name}-${local.resource_suffix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_network_security_rule" "public_tcp" {
  count = length(var.public_service_allowed_cidrs) > 0 ? 1 : 0

  name                        = "allow-public-services-tcp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = local.public_tcp_ports
  source_address_prefixes     = var.public_service_allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.services.name
}

resource "azurerm_network_security_rule" "public_udp" {
  count = length(var.public_service_allowed_cidrs) > 0 ? 1 : 0

  name                        = "allow-public-media-udp"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_ranges     = local.public_udp_ports
  source_address_prefixes     = var.public_service_allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.services.name
}

resource "azurerm_network_security_rule" "private_services" {
  name                        = "allow-vnet-data-and-admin"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = local.private_tcp_ports
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.services.name
}

resource "azurerm_network_security_rule" "ssh" {
  count = length(var.admin_allowed_cidrs) > 0 ? 1 : 0

  name                        = "allow-restricted-ssh"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.admin_allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.services.name
}

resource "azurerm_subnet_network_security_group_association" "environment" {
  for_each = azurerm_subnet.environment

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.services.id
}

#######################################
# Public IP addresses and VM NICs
#######################################

resource "azurerm_public_ip" "environment" {
  for_each = var.environment_instances

  name                = "${var.project_name}-${each.key}-${local.resource_suffix}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(local.common_tags, {
    Environment = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_network_interface" "environment" {
  for_each = var.environment_instances

  name                = "${var.project_name}-${each.key}-${local.resource_suffix}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.environment[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.environment[each.key].id
  }

  tags = merge(local.common_tags, {
    Environment = each.key
  })
}
