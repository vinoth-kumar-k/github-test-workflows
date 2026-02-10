variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-vinoth"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Malaysia West"
}

variable "vm_name" {
  description = "Name of the Windows VM"
  type        = string
  default     = "vm-vbnet-dev"
}

variable "vm_size" {
  description = "Size of the VM (B2s_v2 is minimum viable for Windows)"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "admin_username" {
  description = "Administrator username for the VM"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Administrator password for the VM"
  type        = string
  sensitive   = true
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "vnet-vbnet"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "snet-vbnet"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "allowed_rdp_ips" {
  description = "List of IP addresses allowed to RDP (CIDR notation). Use ['*'] for any (not recommended for production)"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "vbnet-poc"
    ManagedBy   = "terraform"
  }
}
