# providers.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tf-az-webserver-state-rg"
    storage_account_name = "tfazwebsitestate"
    container_name       = "tfstate"
    key                  = "tf-az-webserver.tfstate"
  }
}

provider "azurerm" {
  features {}
}
