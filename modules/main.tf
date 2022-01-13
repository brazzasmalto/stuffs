terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.51.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  name = try(length(var.resource_prefix), 0) > 0 ? "${var.resource_prefix}-trustee_servers" : "trustee_servers"
  uniq = substr(sha1(azurerm_resource_group.trustee.id), 0, 8)
  linux_vm_names = length(var.linux_vm_names) > 0 ? var.linux_vm_names : [for n in range(var.linux_count) :
  format("%s-%02d", var.linux_prefix, n + 1)
  ]

  windows_vm_names = length(var.windows_vm_names) > 0 ? var.windows_vm_names : [for n in range(var.windows_count) :
  format("%s-%02d", var.windows_prefix, n + 1)
  ]
  windows_admin_password = format("%s!", title(random_pet.trustee.id))
  azcmagent = var.azcmagent != null ? var.azcmagent : var.arc != null ? {
    windows = {
      install = true
      connect = true
    }
    linux = {
      install = true
      connect = true
    }
  } : {
    windows = {
      install = false
      connect = false
    }
    linux = {
      install = false
      connect = false
    }
  }
}

###
# Resource groups
###

resource "azurerm_resource_group" "trustee" {
  name     = var.resource_group_name
  location = var.location

  lifecycle {
    ignore_changes = [tags, ]
  }
}

resource "azurerm_ssh_public_key" "trustee" {
  name                = "${local.name}-ssh-public-key"
  resource_group_name = upper(azurerm_resource_group.trustee.name)
  location            = azurerm_resource_group.trustee.location
  public_key          = file(var.admin_ssh_key_file)
}

resource "random_pet" "trustee" {
  length = 2
  keepers = {
    resource_group_id = azurerm_resource_group.trustee.id
  }
}

###
# Networking
###

resource "azurerm_application_security_group" "linux" {
  name                = "${local.name}-linux-asg"
  location            = azurerm_resource_group.trustee.location
  resource_group_name = azurerm_resource_group.trustee.name
}

resource "azurerm_application_security_group" "windows" {
  name                = "${local.name}-windows-asg"
  location            = azurerm_resource_group.trustee.location
  resource_group_name = azurerm_resource_group.trustee.name
}

resource "azurerm_network_security_group" "trustee" {
  name                = "${local.name}-nsg"
  location            = azurerm_resource_group.trustee.location
  resource_group_name = azurerm_resource_group.trustee.name
}

resource "azurerm_virtual_network" "trustee" {
  name                = "${local.name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.trustee.location
  resource_group_name = azurerm_resource_group.trustee.name
}

/*resource "azurerm_subnet" "bastion" {
  for_each             = toset(var.bastion ? ["trustee"] : [])
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.trustee.name
  virtual_network_name = azurerm_virtual_network.trustee.name
  address_prefixes     = ["10.0.0.0/27"]
}
*/

resource "azurerm_subnet" "trustee" {
  name                 = "${local.name}-subnet"
  resource_group_name  = azurerm_resource_group.trustee.name
  virtual_network_name = azurerm_virtual_network.trustee.name
  address_prefixes     = ["10.0.1.0/24"]
}

/*resource "azurerm_subnet_network_security_group_association" "trustee" {
  subnet_id                 = azurerm_subnet.trustee.id
  network_security_group_id = azurerm_network_security_group.trustee.id
}*/

// Bastion

/*resource "azurerm_public_ip" "bastion" {
  for_each            = toset(var.bastion ? ["trustee"] : [])
  name                = "${local.name}-bastion-pip"
  location            = azurerm_resource_group.trustee.location
  resource_group_name = azurerm_resource_group.trustee.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion" {
  for_each            = toset(var.bastion ? ["trustee"] : [])
  name                = "${local.name}-bastion"
  location            = azurerm_resource_group.trustee.location
  resource_group_name = azurerm_resource_group.trustee.name

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion["trustee"].id
    public_ip_address_id = azurerm_public_ip.bastion["trustee"].id
  }
}*/

// Linux virtual machines

module "linux_vms" {
  source              = "vms/linux-vm"
  // source              = "github.com/terraform-azurerm-modules/terraform-azurerm-arc-trustee-linux-vm?ref=v1.0"
  resource_group_name = azurerm_resource_group.trustee.name
  location            = azurerm_resource_group.trustee.location
  tags                = var.tags

  for_each = toset(local.linux_vm_names)

  name                 = each.value
  size                 = var.linux_size
  public_ip            = var.pip && !var.bastion ? true : false
  dns_label            = var.pip && !var.bastion ? "trustee-${local.uniq}-${each.value}" : null
  subnet_id            = azurerm_subnet.trustee.id
  asg_id               = azurerm_application_security_group.linux.id
  admin_username       = var.admin_username
  admin_ssh_public_key = azurerm_ssh_public_key.trustee.public_key

  azcmagent = local.azcmagent.linux.install
  arc       = local.azcmagent.linux.connect ? var.arc : null
}

module "windows_vms" {
  source              = "vms/windows-vm"
  resource_group_name = azurerm_resource_group.trustee.name
  location            = azurerm_resource_group.trustee.location
  tags                = var.tags

  for_each = toset(local.windows_vm_names)

  name           = each.value
  size           = var.windows_size
  public_ip      = var.pip && (each.value == local.windows_vm_names[0] || !var.bastion) ? true : false
  dns_label      = var.pip && (each.value == local.windows_vm_names[0] || !var.bastion) ? "trustee-${local.uniq}-${each.value}" : null
  subnet_id      = azurerm_subnet.trustee.id
  asg_id         = azurerm_application_security_group.windows.id
  admin_username = var.admin_username
  admin_password = local.windows_admin_password

  azcmagent = local.azcmagent.windows.install
  arc       = local.azcmagent.windows.connect ? var.arc : null
}