# Outputs of my TFs
output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "vm_public_ip" {
  value = azurerm_public_ip.vm_pip.ip_address
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "backup_container" {
  value = azurerm_storage_container.backup_container_public.name
}