terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Use existing resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = var.subnet_name
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.vm_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags

  # Allow RDP
  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = var.allowed_rdp_ips
    destination_address_prefix = "*"
  }

  # Allow HTTP
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "pip-${var.vm_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "nic-${var.vm_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Windows Virtual Machine
resource "azurerm_windows_virtual_machine" "main" {
  name                = var.vm_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 127
  }

  # Windows Server 2022 Datacenter (includes .NET Framework 4.8)
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  # Enable boot diagnostics with managed storage
  boot_diagnostics {}

  # Allow Azure VM extensions
  provision_vm_agent         = true
  allow_extension_operations = true

  # Identity for Azure VM Run Command
  identity {
    type = "SystemAssigned"
  }
}

# Custom Script Extension to install IIS
resource "azurerm_virtual_machine_extension" "iis" {
  name                       = "install-iis"
  virtual_machine_id         = azurerm_windows_virtual_machine.main.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Console, Web-Scripting-Tools -IncludeManagementTools; New-Item -Path 'C:\\Deploy' -ItemType Directory -Force; New-Item -Path 'C:\\Backups' -ItemType Directory -Force\""
  })

  tags = var.tags
}

# Storage Account for deployment package staging
resource "azurerm_storage_account" "deploy" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# Storage container for deployment packages
resource "azurerm_storage_container" "deployments" {
  name                  = "deployments"
  storage_account_name  = azurerm_storage_account.deploy.name
  container_access_type = "private"
}

# Role assignment for VM to allow Run Command operations from GitHub Actions
# The Service Principal used by GitHub Actions needs Contributor access to the VM
# This is typically handled at the resource group level
