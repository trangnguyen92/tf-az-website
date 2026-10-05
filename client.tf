# client.tf
resource "azurerm_public_ip" "client" {
  name                = "client-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "client" {
  name                = "client-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.client.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.client.id
  }
}

resource "azurerm_windows_virtual_machine" "client" {
  name                              = "client-vm"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  size                              = "Standard_D2als_v6"
  admin_username                    = var.client_admin_username
  admin_password                    = var.client_admin_password
  vm_agent_platform_updates_enabled = true

  # Azure requires this for hotpatch-enabled images such as azure-edition-core.
  patch_mode = "AutomaticByPlatform"

  network_interface_ids = [
    azurerm_network_interface.client.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition-core"
    version   = "latest"
  }
}
