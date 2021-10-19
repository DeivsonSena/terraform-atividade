terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm =  {
      source  = "hashicorp/azurerm"
      version = ">= 2.46.0"
  }
}
}
provider "azurerm" {
  skip_provider_registration = true
  features {
  }
}

resource "azurerm_resource_group" "example" {
  name     = "example-aulaes22"
  location = "East US"
}

resource "azurerm_virtual_network" "example-aulaes22" {
  name                = "virtualNetwork1"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
  

  tags = {
    environment = "Production"
    turma = "es22"
    faculdade = "impacta"
  }
}

resource "azurerm_subnet" "example-sb-aulaes22" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example-aulaes22.name
  address_prefixes     = ["10.0.1.0/24"]

}
resource "azurerm_public_ip" "example-ip-aulaes22" {
  name                = "acceptanceTestPublicIp1"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}
resource "azurerm_network_security_group" "example-nsg-aulaes22" {
  name                = "acceptanceTestSecurityGroup1"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
 
 security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Production"
  }
}
resource "azurerm_network_interface" "example-nic-aulaes22" {
  name                = "example-nic"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "nic-es22"
    subnet_id                     = azurerm_subnet.example-sb-aulaes22.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.example-ip-aulaes22.id 
  }
}

resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.example-nic-aulaes22.id
  network_security_group_id = azurerm_network_security_group.example-nsg-aulaes22.id
}
resource "azurerm_virtual_machine" "example-vm-aulaes22" {
  name                  = "es22-vm"
  location              = azurerm_resource_group.example.location
  resource_group_name   = azurerm_resource_group.example.name
  network_interface_ids = [azurerm_network_interface.example-nic-aulaes22.id]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}
data "azurerm_public_ip" "ip-db" {
  name                = azurerm_public_ip.example-ip-aulaes22.name
  resource_group_name = azurerm_resource_group.example.name
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_virtual_machine.example-vm-aulaes22]
  create_duration = "30s"
}
resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "testadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.ip-db.ip_address
        }
        source = "mysql"
        destination = "/home/testadmin"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}
resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "testadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.ip-db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/testadmin/mysql/script/user.sql",
            #"sudo mysql < /home/testadmin/mysql/script/schema.sql",
            #"sudo mysql < /home/testadmin/mysql/script/data.sql",
            "sudo cp -f /home/testadmin/mysql/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",]
}
}