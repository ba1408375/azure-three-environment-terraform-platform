locals {
  environment_service_urls = {
    for environment, public_ip in azurerm_public_ip.environment : environment => {
      open_webui            = "http://${public_ip.ip_address}:3000"
      n8n                   = "http://${public_ip.ip_address}:5678"
      nginx                 = "http://${public_ip.ip_address}:8080"
      apache_httpd          = "http://${public_ip.ip_address}:8081"
      tomcat                = "http://${public_ip.ip_address}:8082"
      wildfly               = "http://${public_ip.ip_address}:8083"
      remix                 = "http://${public_ip.ip_address}:8085"
      webxr                 = "http://${public_ip.ip_address}:8090"
      pocketbase            = "http://${public_ip.ip_address}:8091"
      emqx_mqtt             = "mqtt://${public_ip.ip_address}:1883"
      ar                    = "http://${public_ip.ip_address}:8092"
      vr                    = "http://${public_ip.ip_address}:8093"
      api_management        = "http://${public_ip.ip_address}:8000"
      api_management_ar     = "http://${public_ip.ip_address}:8000/ar"
      api_management_vr     = "http://${public_ip.ip_address}:8000/vr"
      api_management_ai     = "http://${public_ip.ip_address}:8000/ai"
      api_management_video  = "http://${public_ip.ip_address}:8000/video"
      api_management_faas   = "http://${public_ip.ip_address}:8000/faas"
      tensorflow_model      = "http://${public_ip.ip_address}:8501/v1/models/half_plus_two"
      mediamtx_hls          = "http://${public_ip.ip_address}:8891/live/index.m3u8"
      mediamtx_webrtc       = "http://${public_ip.ip_address}:8889/live"
      mediamtx_rtsp_example = "rtsp://${public_ip.ip_address}:8554/live"
      mediamtx_rtmp_example = "rtmp://${public_ip.ip_address}:1935/live"
      faas                  = local.function_url
    }
  }

  environment_run_commands = {
    for environment in keys(var.environment_instances) : environment =>
    "az vm run-command invoke --resource-group ${azurerm_resource_group.main.name} --name ${environment} --command-id RunShellScript --scripts \"sudo docker ps\""
  }

  environment_nifi_ssh_tunnels = {
    for environment, public_ip in azurerm_public_ip.environment : environment =>
    "ssh -i azure-key-${var.request_id}.pem -L 8443:127.0.0.1:8443 ${var.admin_username}@${public_ip.ip_address}"
  }
}

#######################################
# Azure environment outputs
#######################################

output "resource_group_name" {
  description = "Azure resource group containing the project"
  value       = azurerm_resource_group.main.name
}

output "environment_instance_ids" {
  description = "Azure Linux VM resource IDs keyed by environment"
  value = {
    for environment, vm in azurerm_linux_virtual_machine.environment :
    environment => vm.id
  }
}

output "environment_public_ips" {
  description = "Static public IP addresses keyed by environment"
  value = {
    for environment, public_ip in azurerm_public_ip.environment :
    environment => public_ip.ip_address
  }
}

output "environment_private_ips" {
  description = "Private VNet IP addresses keyed by environment"
  value = {
    for environment, nic in azurerm_network_interface.environment :
    environment => nic.private_ip_address
  }
}

output "environment_service_urls" {
  description = "Service URLs keyed by dev, test, and production"
  value       = local.environment_service_urls
}

output "environment_run_commands" {
  description = "Azure Run Command examples for checking containers"
  value       = local.environment_run_commands
}

output "environment_ssh_commands" {
  description = "SSH commands; these work only when admin_allowed_cidrs enables port 22"
  value = {
    for environment, public_ip in azurerm_public_ip.environment : environment =>
    "ssh -i azure-key-${var.request_id}.pem ${var.admin_username}@${public_ip.ip_address}"
  }
}

output "azure_function_url" {
  description = "Shared Azure Functions FaaS endpoint"
  value       = local.function_url
}

#######################################
# NiFi private administration
#######################################

output "platform_nifi_username" {
  description = "NiFi single-user login name"
  value       = var.platform_nifi_username
}

output "environment_nifi_passwords" {
  description = "Generated NiFi passwords keyed by environment"
  value = {
    for environment, password in random_password.platform_nifi :
    environment => password.result
  }
  sensitive = true
}

output "environment_nifi_ssh_tunnels" {
  description = "SSH port-forward commands for NiFi; requires a trusted admin CIDR"
  value       = local.environment_nifi_ssh_tunnels
}

#######################################
# Compatibility aliases
#######################################

output "public_ip" {
  description = "Development VM public IP retained as a compatibility alias"
  value       = azurerm_public_ip.environment["dev"].ip_address
}

output "instance_id" {
  description = "Development Azure VM ID retained as a compatibility alias"
  value       = azurerm_linux_virtual_machine.environment["dev"].id
}

output "platform_instance_id" {
  description = "Production Azure VM ID retained as a compatibility alias"
  value       = azurerm_linux_virtual_machine.environment["production"].id
}

output "platform_public_ip" {
  description = "Production public IP retained as a compatibility alias"
  value       = azurerm_public_ip.environment["production"].ip_address
}

output "platform_service_urls" {
  description = "Production service URLs retained as a compatibility alias"
  value       = local.environment_service_urls["production"]
}

output "key_file" {
  description = "Generated Azure VM SSH private-key filename"
  value       = local_sensitive_file.azure_pem.filename
}

output "network_security_group_name" {
  description = "Azure Network Security Group applied to all three subnets"
  value       = azurerm_network_security_group.services.name
}
