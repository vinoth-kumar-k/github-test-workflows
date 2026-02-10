output "resource_group_name" {
  description = "Name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "vm_name" {
  description = "Name of the Windows VM"
  value       = azurerm_windows_virtual_machine.main.name
}

output "vm_id" {
  description = "ID of the Windows VM"
  value       = azurerm_windows_virtual_machine.main.id
}

output "public_ip_address" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "private_ip_address" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.main.private_ip_address
}

output "admin_username" {
  description = "Administrator username"
  value       = var.admin_username
}

output "rdp_connection_string" {
  description = "RDP connection command"
  value       = "mstsc /v:${azurerm_public_ip.main.ip_address}"
}

output "app_url" {
  description = "URL to access the VB.NET application"
  value       = "http://${azurerm_public_ip.main.ip_address}/VBNetApp"
}

output "iis_default_site_url" {
  description = "URL to access the IIS default site"
  value       = "http://${azurerm_public_ip.main.ip_address}"
}

output "storage_account_name" {
  description = "Name of the storage account for deployment staging"
  value       = azurerm_storage_account.deploy.name
}

output "storage_container_name" {
  description = "Name of the storage container for deployments"
  value       = azurerm_storage_container.deployments.name
}

# Outputs for GitHub Actions environment config
output "github_actions_config" {
  description = "Values to add to environments.yml for GitHub Actions"
  value = {
    vm_name           = azurerm_windows_virtual_machine.main.name
    resource_group    = data.azurerm_resource_group.main.name
    storage_account   = azurerm_storage_account.deploy.name
    storage_container = azurerm_storage_container.deployments.name
    iis_site          = "Default Web Site"
    iis_app_name      = "VBNetApp-Dev"
    iis_app_pool      = "VBNetAppPool-Dev"
  }
}
