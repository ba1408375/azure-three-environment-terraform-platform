#######################################
# Azure account and naming
#######################################

variable "azure_subscription_id" {
  description = "Azure subscription ID; omit when ARM_SUBSCRIPTION_ID is set"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.azure_subscription_id == null ||
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.azure_subscription_id))
    )
    error_message = "azure_subscription_id must be a valid UUID when supplied."
  }
}

variable "azure_location" {
  description = "Azure region for every resource"
  type        = string
  default     = "East US"
}

variable "project_name" {
  description = "Short project name used in Azure resource names"
  type        = string
  default     = "devcloud"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,19}$", var.project_name))
    error_message = "project_name must start with a letter and contain 3-20 letters, digits, or hyphens."
  }
}

variable "request_id" {
  description = "Unique request identifier"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$", var.request_id))
    error_message = "request_id must be 1-32 letters, digits, underscores, or hyphens and start with a letter or digit."
  }
}

variable "admin_username" {
  description = "Administrator username for the Azure Linux VMs"
  type        = string
  default     = "azureadmin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{2,31}$", var.admin_username))
    error_message = "admin_username must be a valid lowercase Linux username."
  }
}

#######################################
# Dev, test, and production VM sizing
#######################################

variable "environment_instances" {
  description = "Exactly three Azure VM environments and their capacity"

  type = map(object({
    vm_size         = string
    os_disk_size_gb = number
    subnet_cidr     = string
  }))

  default = {
    dev = {
      vm_size         = "Standard_D8s_v5"
      os_disk_size_gb = 150
      subnet_cidr     = "10.42.10.0/24"
    }
    test = {
      vm_size         = "Standard_D8s_v5"
      os_disk_size_gb = 150
      subnet_cidr     = "10.42.20.0/24"
    }
    production = {
      vm_size         = "Standard_D16s_v5"
      os_disk_size_gb = 300
      subnet_cidr     = "10.42.30.0/24"
    }
  }

  validation {
    condition     = toset(keys(var.environment_instances)) == toset(["dev", "test", "production"])
    error_message = "environment_instances must contain exactly dev, test, and production."
  }

  validation {
    condition = alltrue([
      for environment in values(var.environment_instances) :
      environment.os_disk_size_gb >= 100
    ])
    error_message = "Each environment needs at least 100 GB for images and persistent Docker volumes."
  }

  validation {
    condition = alltrue([
      for environment in values(var.environment_instances) :
      can(cidrnetmask(environment.subnet_cidr))
    ])
    error_message = "Each subnet_cidr must be a valid IPv4 CIDR."
  }

  validation {
    condition = (
      length(distinct([
        for environment in values(var.environment_instances) :
        environment.subnet_cidr
      ])) == length(var.environment_instances) &&
      alltrue([
        for environment in values(var.environment_instances) :
        startswith(environment.subnet_cidr, "10.42.") &&
        endswith(environment.subnet_cidr, "/24") &&
        split("/", environment.subnet_cidr)[0] == cidrhost(environment.subnet_cidr, 0)
      ])
    )
    error_message = "Each environment needs a unique 10.42.x.0/24 subnet inside the project VNet."
  }
}

#######################################
# Network access
#######################################

variable "public_service_allowed_cidrs" {
  description = "Trusted CIDRs allowed to reach demonstration service ports; empty disables public service access"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.public_service_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "public_service_allowed_cidrs must contain only valid IPv4 CIDRs."
  }
}

variable "admin_allowed_cidrs" {
  description = "Trusted CIDRs allowed to use SSH; empty disables public SSH"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.admin_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "admin_allowed_cidrs must contain only valid IPv4 CIDRs."
  }
}

#######################################
# Existing core service credentials
#######################################

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

variable "mysql_database" {
  description = "MySQL database"
  type        = string
}

variable "mysql_user" {
  description = "MySQL application user"
  type        = string
}

variable "mysql_password" {
  description = "MySQL application password"
  type        = string
  sensitive   = true
}

variable "mariadb_root_password" {
  description = "MariaDB root password"
  type        = string
  sensitive   = true
}

variable "mariadb_database" {
  description = "MariaDB database"
  type        = string
}

variable "mariadb_user" {
  description = "MariaDB application user"
  type        = string
}

variable "mariadb_password" {
  description = "MariaDB application password"
  type        = string
  sensitive   = true
}

variable "postgres_user" {
  description = "PostgreSQL user"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "postgres_database" {
  description = "PostgreSQL database"
  type        = string
}

variable "mongodb_user" {
  description = "MongoDB administrator user"
  type        = string
}

variable "mongodb_password" {
  description = "MongoDB administrator password"
  type        = string
  sensitive   = true
}

variable "jupyter_token" {
  description = "Jupyter Notebook access token"
  type        = string
  sensitive   = true
}

#######################################
# Added platform services
#######################################

variable "platform_nifi_username" {
  description = "Single-user administrator name for NiFi"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.platform_nifi_username) >= 4
    error_message = "platform_nifi_username must contain at least four characters."
  }
}

variable "platform_images" {
  description = "Pinned images used by the six added Docker services"

  type = object({
    static_web = string
    tensorflow = string
    kong       = string
    nifi       = string
    mediamtx   = string
  })

  default = {
    static_web = "nginx:1.28.0-alpine"
    tensorflow = "tensorflow/serving:2.20.0"
    kong       = "kong/kong-gateway:3.10.0.2"
    nifi       = "apache/nifi:2.10.0"
    mediamtx   = "bluenviron/mediamtx:1.18.2"
  }
}

variable "function_plan_sku" {
  description = "Linux App Service plan SKU used by the Azure Function"
  type        = string
  default     = "B1"
}

variable "function_python_version" {
  description = "Python runtime used by Azure Functions v4"
  type        = string
  default     = "3.12"
}

variable "common_tags" {
  description = "Additional tags applied to Azure resources"
  type        = map(string)
  default     = {}
}
