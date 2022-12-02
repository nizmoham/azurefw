# Provider

provider "azurerm" {
            subscription_id = "810dd244-8648-42e6-9fb1-b1df5817f269"
            client_id = "4f4f74e6-8fbc-4a5b-80e4-6405216aca0b"
            client_secret = "5crrp--81X6_sW~3UietI5-vS5nAgi6~xJ"
            tenant_id = "66b66353-3b76-4e41-9dc3-fee328bd400e"
            features {}
        }

# User Inputs

variable "resource_group" {
  description = "Provide a name for the resource group: "
}

variable "region" {
  description = "Provide a region for deployment. ex: eastus, eastus2, westus, westus2, centralus, northcentralus, southcentralus, northeurope, westeurope, westcentralus, etc."
}

variable "platform" {
  description = "Choose a platform. ex: VM-300 VM-500 VM-700"
}

variable "source_ip" {
  description = "Provide the public IP of your machine with /32 mask ex: 1.1.1.1/32"
}

# Storage Account

variable "storage_account" {
  default = "tacautoboot"
}

variable "access_key" {
  default = "ADgGrztE2eAYmwyRuNvydhEKzCFkMvPBiEBVo8+vYt3O6mEcmozMgV+we9kKs17hTyQJ4Z0lJPn55gyzK6A/8Q=="
}

variable "share_directory" {
  default = "firewall"
}

variable "file_share" {
  default = {
    VM-300="bootstrap-vm-300"
    VM-500="bootstrap-vm-500"
    VM-700="bootstrap-vm-700"
  }
}

# Other variables

variable "instance_size" {
  default = {
    VM-300 = "Standard_D3_v2"
    VM-500 = "Standard_D4_v2"
    VM-700 = "Standard_D5_v2"
  }
}


# Create Resource Group

resource "azurerm_resource_group" "rg" {
  name = var.resource_group
  location = var.region
}

# Create Virtual Network

resource "azurerm_virtual_network" "vnet" {
    name                = "TF-VNET"
    address_space       = ["10.10.0.0/16"]
    location            = var.region
    resource_group_name = azurerm_resource_group.rg.name
}

# Create Subnets

resource "azurerm_subnet" "mgmt_subnet" {
    name                 = "mgmt_subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.10.10.0/24"]
}
resource "azurerm_subnet" "untrust_subnet" {
    name                 = "untrust_subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.10.11.0/24"]
}
resource "azurerm_subnet" "trust_subnet" {
    name                 = "trust_subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.10.12.0/24"]
}

# Create NSG and rules

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "allow-inbound" {
  name                        = "az-inbound"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges      = ["443","22","80"]
  source_address_prefix       = var.source_ip
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# Associate NSG with subnets

resource "azurerm_subnet_network_security_group_association" "nsg_mgmt" {
  subnet_id                 = azurerm_subnet.mgmt_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_untrust" {
  subnet_id                 = azurerm_subnet.untrust_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create and associate route table

resource "azurerm_route_table" "route_tbl_trust" {
  name                = "route_tbl_trust"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name

  route {
    name           = "default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.10.12.4"
  }

}

resource "azurerm_subnet_route_table_association" "rt_trust" {
  subnet_id      = azurerm_subnet.trust_subnet.id
  route_table_id = azurerm_route_table.route_tbl_trust.id
}


# Create public IP's

resource "azurerm_public_ip" "pub_ip_mgmt" {
  name                = "pub_ip_mgmt"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  idle_timeout_in_minutes = 30
}

resource "azurerm_public_ip" "pub_ip_untrust" {
  name                = "pub_ip_untrust"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

# Create Network Interfaces

resource "azurerm_network_interface" "fw01-eth0" {
  name                = "fw01-eth0"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
    name                          = "fw01-eth0-config"
    subnet_id                     = azurerm_subnet.mgmt_subnet.id
    private_ip_address_allocation  = "Static"
    public_ip_address_id          = azurerm_public_ip.pub_ip_mgmt.id
	private_ip_address 			  = "10.10.10.4"
  }
}

resource "azurerm_network_interface" "fw01-eth1" {
  name                = "fw01-eth1"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
    name                          = "fw01-eth1-config"
    subnet_id                     = azurerm_subnet.untrust_subnet.id
    private_ip_address_allocation  = "Static"
    public_ip_address_id          = azurerm_public_ip.pub_ip_untrust.id
	private_ip_address 			  = "10.10.11.4"
  }
}


resource "azurerm_network_interface" "fw01-eth2" {
  name                = "fw01-eth2"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
    name                          = "eth2-config"
    subnet_id                     = azurerm_subnet.trust_subnet.id
    private_ip_address_allocation  = "Static"
	private_ip_address 			  = "10.10.12.4"
  }
}

# Creating VM-Series Firewall

resource "azurerm_virtual_machine" "fw01" {
  name                  = "fw01"
  location              = var.region
  resource_group_name   = azurerm_resource_group.rg.name
  vm_size               = var.instance_size[var.platform]
  primary_network_interface_id = azurerm_network_interface.fw01-eth0.id

  network_interface_ids = [azurerm_network_interface.fw01-eth0.id,
                           azurerm_network_interface.fw01-eth1.id,
                           azurerm_network_interface.fw01-eth2.id
                          ]

  depends_on = [azurerm_network_interface.fw01-eth0,
                azurerm_network_interface.fw01-eth1,
                azurerm_network_interface.fw01-eth2
                ]

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  plan {
    name = "byol"
    publisher = "paloaltonetworks"
    product = "vmseries-flex"
  }

  storage_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = "byol"
    version   = "10.2.3"
  }

  storage_os_disk {
    name              = "fw01_osdisk"
    disk_size_gb      = "60"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "fw01"
    admin_username = "palouser"
    admin_password = "PaloAlto123!"
	custom_data = base64encode(join(", ", ["storage-account= var.storage_account", "access-key= var.access_key", "file-share= var.file_share[var.platform]", "share-directory= var.share_directory"]))
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

}




