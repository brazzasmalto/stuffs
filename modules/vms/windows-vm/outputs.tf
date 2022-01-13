output "fqdn" {
  value = var.public_ip ? azurerm_public_ip.trustee["pip"].fqdn : null
}

output "public_ip_address" {
  value = var.public_ip ? azurerm_public_ip.trustee["pip"].ip_address : null
}