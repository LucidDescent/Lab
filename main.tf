terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}
#Should find more secure alternative
provider "azurerm" {
  features {}

  subscription_id = "(Enter Subscription ID Here)"
  tenant_id       = "(Enter Tenant ID Here)"
  client_id       = "(Enter Client ID Here)"
  client_secret   = "(Enter Client Secret Here)"
}

#Creates primary resource group
resource "azurerm_resource_group" "coalfireGroup" {
  name     = "coalfireTest"
  location = "eastus2"
}

#Creates underlying VNet
resource "azurerm_virtual_network" "coalfireVNet" {
  name                = "coalfireVNet"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.coalfireGroup.name
}

resource "azurerm_subnet" "coalfireSubnet1" {
  name                 = "sub1"
  resource_group_name  = azurerm_resource_group.coalfireGroup.name
  virtual_network_name = azurerm_virtual_network.coalfireVNet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "coalfireSubnet2" {
  name                 = "sub2"
  resource_group_name  = azurerm_resource_group.coalfireGroup.name
  virtual_network_name = azurerm_virtual_network.coalfireVNet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "coalfireSubnet3" {
  name                 = "sub3"
  resource_group_name  = azurerm_resource_group.coalfireGroup.name
  virtual_network_name = azurerm_virtual_network.coalfireVNet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "coalfireSubnet4" {
  name                 = "sub4"
  resource_group_name  = azurerm_resource_group.coalfireGroup.name
  virtual_network_name = azurerm_virtual_network.coalfireVNet.name
  address_prefixes     = ["10.0.3.0/24"]
}

#Network Security Group NSG1, for use with havm
resource "azurerm_network_security_group" "coalfireNSG1" {
  name                = "coalfireNetworkSecurityGroup1"
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.coalfireGroup.name

  security_rule {
    name                       = "SSH"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "10.0.0.0/16"
  }

  #tags {}
}

#Network Security Group NSG2, for use with apachevm
resource "azurerm_network_security_group" "coalfireNSG2" {
  name                = "coalfireNetworkSecurityGroup2"
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.coalfireGroup.name

  security_rule {
    name                       = "AllAllow"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "10.0.0.0/16"
  }

  #Allow HTTP
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 3999
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = azurerm_network_interface.apachevmnic.private_ip_address
  }

  #Allow SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 3998
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = azurerm_network_interface.apachevmnic.private_ip_address
  }

  #Allow All Out
  security_rule {
    name                       = "AllowAllOut"
    priority                   = 3000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  #tags {}
}

#Public IP for Azure Loadbalancer
resource "azurerm_public_ip" "apacheip" {
  name                = "apachepublicIP"
  location            = azurerm_resource_group.coalfireGroup.location
  resource_group_name = azurerm_resource_group.coalfireGroup.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

#Azure load balancer, for use with apachevm
resource "azurerm_lb" "apachelb" {
  name                = "ApacheLoadbalancer"
  location            = azurerm_resource_group.coalfireGroup.location
  resource_group_name = azurerm_resource_group.coalfireGroup.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "publicAccess"
    public_ip_address_id = azurerm_public_ip.apacheip.id
  }
}

#Apache load balancer, backend
resource "azurerm_lb_backend_address_pool" "apachelbbackend" {
  loadbalancer_id = azurerm_lb.apachelb.id
  name            = "ApacheLBBackEndPool"
}

#Azure load balancer, backend pool association
resource "azurerm_network_interface_backend_address_pool_association" "apachelbassociate" {
  network_interface_id    = azurerm_network_interface.apachevmnic.id
  ip_configuration_name   = "apachevmNicConfig"
  backend_address_pool_id = azurerm_lb_backend_address_pool.apachelbbackend.id
}

#Azure load balancer, load balancing rule for http
#Need replace backend_address_pool_id; deprecated function
resource "azurerm_lb_rule" "apachelbhttp" {
  name                           = "ApacheLBHTTPIn"
  resource_group_name            = azurerm_resource_group.coalfireGroup.name
  loadbalancer_id                = azurerm_lb.apachelb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "publicAccess"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.apachelbbackend.id
}

#Azure load balancer, load balancing rule for ssh
#Need replace backend_address_pool_id; deprecated function
resource "azurerm_lb_rule" "apachelbssh" {
  name                           = "ApacheLBSSHIn"
  resource_group_name            = azurerm_resource_group.coalfireGroup.name
  loadbalancer_id                = azurerm_lb.apachelb.id
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = "publicAccess"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.apachelbbackend.id
}

#SSH Key
resource "tls_private_key" "testkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

output "tls_private_key" {
  value     = tls_private_key.testkey.private_key_pem
  sensitive = true
}

#Network Interfaces for havm
resource "azurerm_network_interface" "hanic" {
  count               = 2
  name                = "hanic${count.index}"
  location            = azurerm_resource_group.coalfireGroup.location
  resource_group_name = azurerm_resource_group.coalfireGroup.name

  ip_configuration {
    name                          = "haNicConfig"
    subnet_id                     = azurerm_subnet.coalfireSubnet1.id
    private_ip_address_allocation = "dynamic"
  }
}

#Network Interface for ApacheVM
resource "azurerm_network_interface" "apachevmnic" {
  name                = "apachevmnic"
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.coalfireGroup.name

  ip_configuration {
    name                          = "apachevmNicConfig"
    subnet_id                     = azurerm_subnet.coalfireSubnet3.id
    private_ip_address_allocation = "dynamic"
    #public_ip_address_id = 
  }
}

#iterates through the hanic instances and associates them with coalfireNSG1
resource "azurerm_network_interface_security_group_association" "hanicNSG" {
  count                     = length(azurerm_network_interface.hanic)
  network_interface_id      = azurerm_network_interface.hanic[count.index].id
  network_security_group_id = azurerm_network_security_group.coalfireNSG1.id
}

#associates the apachevmnic to coalfireNSG2
resource "azurerm_network_interface_security_group_association" "apachevmnicNSG" {
  network_interface_id      = azurerm_network_interface.apachevmnic.id
  network_security_group_id = azurerm_network_security_group.coalfireNSG2.id
}

#Availability set for the HAVMs
resource "azurerm_availability_set" "haset" {
  name                         = "haset"
  location                     = azurerm_resource_group.coalfireGroup.location
  resource_group_name          = azurerm_resource_group.coalfireGroup.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}

#VMs
resource "azurerm_linux_virtual_machine" "havms" {
  count                 = 2
  name                  = "havm${count.index}"
  location              = azurerm_resource_group.coalfireGroup.location
  resource_group_name   = azurerm_resource_group.coalfireGroup.name
  availability_set_id   = azurerm_availability_set.haset.id
  network_interface_ids = [element(azurerm_network_interface.hanic.*.id, count.index)]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "havmdisk${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = "256"
  }

  source_image_reference {
    publisher = "Redhat"
    offer     = "RHEL"
    sku       = "7.3"
    version   = "latest"
  }

  computer_name                   = "havm${count.index}"
  admin_username                  = "cloudadmin"
  admin_password                  = "Test123123!!!"
  disable_password_authentication = false

  admin_ssh_key {
    username   = "cloudadmin"
    public_key = tls_private_key.testkey.public_key_openssh
  }
}

resource "azurerm_linux_virtual_machine" "apachevm" {
  name                  = "apachevm"
  location              = "eastus2"
  resource_group_name   = azurerm_resource_group.coalfireGroup.name
  network_interface_ids = [azurerm_network_interface.apachevmnic.id]
  size                  = "Standard_DS1_v2"


  os_disk {
    name                 = "apachevmDisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    #Does not accept 32 GB
    #disk_size_gb = "32"
    disk_size_gb = "64"
  }

  source_image_reference {
    publisher = "Redhat"
    offer     = "RHEL"
    sku       = "7.3"
    version   = "latest"
  }

  computer_name                   = "apachevm"
  admin_username                  = "cloudadmin"
  admin_password                  = "Test123123!!!"
  disable_password_authentication = false

  admin_ssh_key {
    username   = "cloudadmin"
    public_key = tls_private_key.testkey.public_key_openssh
  }

  provisioner "remote-exec" {
    inline = [
      "echo Test123123!!! | sudo -S yum update -y --disablerepo='*' --enablerepo='*microsoft*'",
      "sudo yum install httpd -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo firewall-cmd --zone=public --permanent --add-service=http",
      "sudo firewall-cmd --reload",
    ]
    connection {
      type        = "ssh"
      host        = azurerm_public_ip.apacheip.ip_address
      user        = "cloudadmin"
      private_key = tls_private_key.testkey.private_key_pem
    }
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.coalStorage.primary_blob_endpoint
  }
}

resource "azurerm_storage_account" "coalStorage" {
  name                     = "coalstorage1294813451"
  resource_group_name      = azurerm_resource_group.coalfireGroup.name
  location                 = azurerm_resource_group.coalfireGroup.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}