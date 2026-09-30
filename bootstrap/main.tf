# bootstrap/main.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "northeurope"
}

resource "azurerm_resource_group" "state" {
  name     = "tf-az-webserver-state-rg"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                     = "tfazwebsitestate"
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.state.name
  container_access_type = "private"
}

output "storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "resource_group_name" {
  value = azurerm_resource_group.state.name
}
