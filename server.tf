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
  size                = "Standard_B1s"
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

  # Load-bearing ordering inside cloud-init/server.yaml: cloud-init runs
  # `write_files` BEFORE `packages` installs nginx, and the "Hello World" page
  # survives only because Ubuntu's nginx package does not overwrite an existing
  # /var/www/html/index.html. A future reordering or a different web server
  # package would silently clobber it.
  #
  # NOTE: any edit to cloud-init/server.yaml — including a comment — changes
  # custom_data, which forces replacement of this VM. Treat edits to that file
  # as destructive and plan them deliberately.
  custom_data = base64encode(file("${path.module}/cloud-init/server.yaml"))

  # cloud-init needs outbound internet to `apt install nginx`, and this
  # subnet's only route out is the NAT gateway. Without this, a from-scratch
  # apply can create the VM before the NAT association finishes and cloud-init
  # fails with no internet access.
  depends_on = [azurerm_subnet_nat_gateway_association.server]
}
