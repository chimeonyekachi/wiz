
# rg
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# VN & SubNet; 1 AKS private, 1 for VM
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "vm_subnet" {
  name                 = "${var.prefix}-vm-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Public IP for LB | AKS to auto-create LB
resource "azurerm_public_ip" "vm_pip" {
  name                = "${var.prefix}-vm-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NSG for VM with SSH to internet
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "${var.prefix}-vm-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "allow_ssh_internet" {
  name                        = "AllowSSHFromInternet"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.vm_nsg.name
}

# NIC for VM
resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.prefix}-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }
}

# Storage Account (for mongo backups)
resource "azurerm_storage_account" "storage" {
  name                      = lower("${var.prefix}storage${random_integer.suffix.result}")
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  allow_nested_items        = true
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = false
}

resource "random_integer" "suffix" {
  min = 1000
  max = 9999
}

# Blob container with Public access
resource "azurerm_storage_container" "backup_container" {
  name                  = var.backup_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "blob"
}

# Making the container publicly listable
resource "azurerm_storage_container" "backup_container_public" {
  name                  = var.backup_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "container" # allows public list
  depends_on            = [azurerm_storage_account.storage]
}

# Managed Identity for VM via system_assigned
resource "azurerm_linux_virtual_machine" "mongo_vm" {
  name                            = "${var.prefix}-mongo-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B2s"
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.vm_nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18_04-lts"    # SKU with outdated 1+ year
    version   = "18.04.202104" # Older image
  }

  //   # calling cloud-init script to install old mongodb and schedule backups
  //   custom_data = base64encode(file("${path.module}/cloud-init-mongo.yaml"))

  identity {
    type = "SystemAssigned"
  }
}

# VM's identity Contributor role at subscription = overly permissive
data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "vm_identity_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.mongo_vm.identity[0].principal_id
}

# AKS cluster with ACR integration
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-aks"

  default_node_pool {
    name           = "agentpool"
    node_count     = var.aks_node_count
    vm_size        = var.aks_node_size
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  linux_profile {
    admin_username = var.admin_username
    ssh_key {
      key_data = var.ssh_public_key
    }
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  # since enable HTTP application routing disabled by default; 
  # ingress will be user-managed
}

# ACR
resource "azurerm_container_registry" "acr" {
  name                = lower("${var.prefix}acr${random_integer.suffix.result}")
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false
}

# AKS's identity pull on ACR - RBAC
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

