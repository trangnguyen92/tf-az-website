# outputs.tf
output "server_private_ip" {
  description = "Private IP address of the Ubuntu server VM"
  value       = azurerm_network_interface.server.private_ip_address
}

output "client_public_ip" {
  description = "Public IP address of the Windows client VM (RDP here)"
  value       = azurerm_public_ip.client.ip_address
}
