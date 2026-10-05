# server.tf
resource "azurerm_network_interface" "server" {
  name                = "server-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.server.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "server" {
  name                = "server-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_D2als_v6"
  admin_username      = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.server.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.server_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # NOTE: any edit to cloud-init/server.yaml — including a comment — changes
  # custom_data, which forces replacement of this VM. Page content lives in
  # site/index.html instead (see the extension below), so it can change in place.
  custom_data = base64encode(file("${path.module}/cloud-init/server.yaml"))

  # cloud-init needs outbound internet to `apt install nginx`, and this
  # subnet's only route out is the NAT gateway. Without this, a from-scratch
  # apply can create the VM before the NAT association finishes and cloud-init
  # fails with no internet access.
  depends_on = [azurerm_subnet_nat_gateway_association.server]
}

# Writes site/index.html onto the server. Changing the page changes `settings`,
# which updates this extension in place and re-runs the command — the VM is
# not replaced. Waiting for cloud-init first ensures nginx is installed.
resource "azurerm_virtual_machine_extension" "server_web_content" {
  name                       = "web-content"
  virtual_machine_id         = azurerm_linux_virtual_machine.server.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "cloud-init status --wait; mkdir -p /var/www/html && echo ${base64encode(file("${path.module}/site/index.html"))} | base64 -d > /var/www/html/index.html"
  })
}
