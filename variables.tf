# variables.tf
variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group that holds all project resources"
  type        = string
  default     = "tf-az-webserver-rg"
}

variable "operator_ips" {
  description = "Public IP addresses in CIDR form (e.g. [\"203.0.113.5/32\"]) allowed to RDP into the client VM"
  type        = list(string)
}

variable "client_admin_username" {
  description = "Local admin username for the Windows client VM"
  type        = string
  default     = "azureadmin"
}

variable "client_admin_password" {
  description = "Local admin password for the Windows client VM"
  type        = string
  sensitive   = true
}

variable "server_ssh_public_key" {
  description = "SSH public key installed on the Ubuntu server VM"
  type        = string
}
