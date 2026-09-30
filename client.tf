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
  name                = "client-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B1s"
  admin_username      = var.client_admin_username
  admin_password      = var.client_admin_password

  # "azure-edition-core" is a hotpatch-enabled image (hotpatch requires
  # Server Core — the Desktop Experience "azure-edition" this replaced is
  # NOT hotpatch-enabled, which is why this wasn't needed before). Azure
  # requires patch_mode = "AutomaticByPlatform" for any hotpatch image.
  patch_mode = "AutomaticByPlatform"

  network_interface_ids = [
    azurerm_network_interface.client.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Server Core (no GUI shell) — the Desktop Experience edition this replaced
  # needs 2 GiB RAM minimum per Microsoft, but this VM is Standard_B1s (1 GiB
  # free-tier). Running the GUI shell left too little memory for new
  # processes to initialize, causing PowerShell to crash with 0xc0000142.
  # RDP into this VM now lands directly in a console (no desktop/taskbar) —
  # that's expected, not a bug; run `powershell` or `cmd` from there.
  #
  # NOTE: changing this SKU string forces replacement of this VM (ForceNew).
  # The public IP (azurerm_public_ip.client) and admin credentials are
  # separate resources/variables and are unaffected — only this VM instance
  # is destroyed and recreated.
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition-core"
    version   = "latest"
  }
}
