terraform {
  experiments = [module_variable_optional_attrs]
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.59.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
  required_version = ">= 0.13"
}

provider "azurerm" {
  features {}
}

module "dev" {
  source = "live/dev"
}

/*
module "uat" {
  source = "live/uat"
}

module "prod" {
  source = "live/prod"
}*/
