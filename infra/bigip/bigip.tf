
# Create a Public IP for the Virtual Machines
resource "azurerm_public_ip" "vm01mgmtpip" {
  name                         = "${var.prefix}-vm01-mgmt-pip"
  location                     = "${var.location}"
  resource_group_name          = "${var.rg_name}"
  sku                          = "Standard"
  allocation_method            = "Static"
}



resource "azurerm_public_ip" "lbpip" {
  name                         = "${var.prefix}-lb-pip"
  location                     = "${var.location}"
  resource_group_name          = "${var.rg_name}"
  sku                          = "Standard"
  allocation_method            = "Static"
  domain_name_label            = "${var.prefix}lbpip"
}




# Create a Network Security Group with some rules
resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-nsg"
  location            = "${var.location}"
  resource_group_name = "${var.rg_name}"

  security_rule {
    name                       = "allow_SSH"
    description                = "Allow SSH access"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_HTTP"
    description                = "Allow HTTP access"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_HTTPS"
    description                = "Allow HTTPS access"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_RDP"
    description                = "Allow RDP access"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_APP_HTTPS"
    description                = "Allow HTTPS access"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  #this explicit dependency is not needed for creation (terraform apply) but can be useful when deleting resources where deleting a VM and NSG at the same time may cause conflicts with simultaneous NIC updates
  depends_on           = ["azurerm_virtual_machine.f5vm01"]
}

# Create the first network interface card for Management 
resource "azurerm_network_interface" "vm01-mgmt-nic" {
  name                      = "${var.prefix}-vm01-mgmt-nic"
  location                  = "${var.location}"
  resource_group_name       = "${var.rg_name}"
  #network_security_group_id = "${azurerm_network_security_group.main.id}"

  ip_configuration {
    name                          = "primary"
    subnet_id                     = "${var.mgmt_subnet_id}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${var.f5vm01mgmt}"
    public_ip_address_id          = "${azurerm_public_ip.vm01mgmtpip.id}"
  }
}


# Create the second network interface card for External
resource "azurerm_network_interface" "vm01-ext-nic" {
  name                = "${var.prefix}-vm01-ext-nic"
  location                  = "${var.location}"
  resource_group_name       = "${var.rg_name}"
  #network_security_group_id = "${azurerm_network_security_group.main.id}"
  #depends_on          = ["azurerm_lb_backend_address_pool.backend_pool"]

  ip_configuration {
    name                          = "primary"
    subnet_id                     = "${var.external_subnet_id}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${var.f5vm01ext}"
    primary			  = true
  }

  ip_configuration {
    name                          = "secondary"
    subnet_id                     = "${var.external_subnet_id}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${var.f5vm01ext_sec}"
  }
}

# Create the third network interface card for Internal
resource "azurerm_network_interface" "vm01-int-nic" {
  name                = "${var.prefix}-vm01-int-nic"
  location                  = "${var.location}"
  resource_group_name       = "${var.rg_name}"
  #network_security_group_id = "${azurerm_network_security_group.main.id}"

  ip_configuration {
    name                          = "primary"
    subnet_id                     = "${var.internal_subnet_id}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${var.f5vm01int}"
    primary			  = true
  }
}


#Associate NIC's with security groups
resource "azurerm_network_interface_security_group_association" "nsgassociation1" {
  network_interface_id      = azurerm_network_interface.vm01-mgmt-nic.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_network_interface_security_group_association" "nsgassociation3" {
  network_interface_id      = azurerm_network_interface.vm01-ext-nic.id
  network_security_group_id = azurerm_network_security_group.main.id
}




# Setup Onboarding scripts
data "template_file" "vm_onboard_device1" {
  template = "${file("${path.module}/onboard.tpl")}"

  vars = {
    uname        	  = "${var.uname}"
    upassword        	  = "${var.upassword}"
    DO_onboard_URL        = "${var.DO_onboard_URL}"
    AS3_URL		  = "${var.AS3_URL}"
    libs_dir		  = "${var.libs_dir}"
    onboard_log		  = "${var.onboard_log}"
    hostname     = "${var.host1_name}"
  }
}


data "template_file" "vm01_do_json" {
  template = "${file("${path.module}/cluster.json")}"

  vars = {
    #Uncomment the following line for BYOL
    #local_sku	    = "${var.license1}"

    host1	    = "${var.host1_name}"
    local_host      = "${var.host1_name}"
    local_selfip    = "${var.f5vm01ext}"
    local_selfip2    = "${var.f5vm01int}"
    gateway	    = "${var.ext_gw}"
    dns_server	    = "${var.dns_server}"
    ntp_server	    = "${var.ntp_server}"
    timezone	    = "${var.timezone}"
    admin_user      = "${var.uname}"
    admin_password  = "${var.upassword}"
  }
}



# Create F5 BIGIP VMs
resource "azurerm_virtual_machine" "f5vm01" {
  name                         = "${var.prefix}-f5vm01"
  location                     = "${var.location}"
  resource_group_name          = "${var.rg_name}"
  primary_network_interface_id = "${azurerm_network_interface.vm01-mgmt-nic.id}"
  network_interface_ids        = ["${azurerm_network_interface.vm01-mgmt-nic.id}", "${azurerm_network_interface.vm01-ext-nic.id}", "${azurerm_network_interface.vm01-int-nic.id}"]
  vm_size                      = "${var.instance_type}"
  # availability_set_id          = "${azurerm_availability_set.avset.id}"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
   delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
   delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "f5-networks"
    offer     = "${var.product}"
    sku       = "${var.image_name}"
    version   = "${var.bigip_version}"
  }

  storage_os_disk {
    name              = "${var.prefix}vm01-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.prefix}vm01"
    admin_username = "${var.uname}"
    admin_password = "${var.upassword}"
    custom_data    = "${data.template_file.vm_onboard_device1.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  plan {
    name          = "${var.image_name}"
    publisher     = "f5-networks"
    product       = "${var.product}"
  }
}



# Run REST API for configuration
resource "local_file" "vm01_do_file" {
  content     = "${data.template_file.vm01_do_json.rendered}"
  filename    = "${path.module}/vm01_do_data.json"
}



resource "null_resource" "f5vm01-run-REST" {
  depends_on = [
    "azurerm_network_interface_security_group_association.nsgassociation1",
    # "azurerm_network_interface_security_group_association.nsgassociation2",
    "local_file.vm01_do_file"
    ]
  # Running DO REST API
  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      sleep 15
      curl -k -X GET https://${data.azurerm_public_ip.vm01mgmtpip.ip_address}${var.rest_do_uri} -u ${var.uname}:${var.upassword}
      sleep 10
      curl -k -X ${var.rest_do_method} https://${data.azurerm_public_ip.vm01mgmtpip.ip_address}${var.rest_do_uri} -u ${var.uname}:${var.upassword} -d @./${path.module}/${var.rest_vm01_do_file}
    EOF
  }

}



## OUTPUTS ###
data "azurerm_public_ip" "vm01mgmtpip" {
  name                = "${azurerm_public_ip.vm01mgmtpip.name}"
  resource_group_name = "${var.rg_name}"
}


output "sg_id" { value = "${azurerm_network_security_group.main.id}" }
output "sg_name" { value = "${var.rg_name}" }
output "mgmt_subnet_gw" { value = "${var.mgmt_gw}" }
output "ext_subnet_gw" { value = "${var.ext_gw}" }
# output "ALB_app1_pip" { value = "${data.azurerm_public_ip.lbpip.ip_address}" }

output "f5vm01_id" { value = "${azurerm_virtual_machine.f5vm01.id}"  }
output "f5vm01_mgmt_private_ip" { value = "${azurerm_network_interface.vm01-mgmt-nic.private_ip_address}" }
output "f5vm01_mgmt_public_ip" { value = "${data.azurerm_public_ip.vm01mgmtpip.ip_address}" }
output "f5vm01_ext_private_ip" { value = "${azurerm_network_interface.vm01-ext-nic.private_ip_address}" }

