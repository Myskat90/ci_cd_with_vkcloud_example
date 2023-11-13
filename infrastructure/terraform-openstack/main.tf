#variable "auth_url" {}
#variable "password" {}
#variable "user_name" {}
#variable "tenant_name" {}
#variable "region" {}

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.51.1"
    }
  }
}

provider "openstack" {
  #  user_name   = var.user_name
  #  tenant_name = var.tenant_name
  #  password    = var.password
  cloud = "openstack"
  #  region      = var.region
}

#-----------
## Create ext-network
#-----------
resource "openstack_networking_network_v2" "ext-network" {
  name           = "ext-network"
  admin_state_up = "true"
  external       = "true"
  segments {
    network_type     = "flat"
    physical_network = "physnet1"
  }
}

#-----------
## Create ext-subnet
#-----------
resource "openstack_networking_subnet_v2" "ext-subnet" {
  name            = "ext-subnet"
  network_id      = openstack_networking_network_v2.ext-network.id
  cidr            = "192.168.2.0/23"
  gateway_ip      = "192.168.2.1"
  dns_nameservers = ["192.168.2.254", "192.168.5.254"]
  enable_dhcp     = "false"
  allocation_pool {
    start = "192.168.3.80"
    end   = "192.168.3.120"
  }
}

#-----------
## Create external-router
#-----------
resource "openstack_networking_router_v2" "external-router" {
  name                = "external-router"
  admin_state_up      = "true"
  enable_snat         = "false"
  external_network_id = openstack_networking_network_v2.ext-network.id
}

#-----------
## Create int-network
#-----------
resource "openstack_networking_network_v2" "int-network" {
  name           = "int-network"
  admin_state_up = "true"
}

#-----------
## Create int-subnet-1
#-----------
resource "openstack_networking_subnet_v2" "int-subnet-1" {
  network_id = openstack_networking_network_v2.int-network.id
  name       = "int-subnet-1"
  cidr       = "10.10.1.0/24"
  gateway_ip = "10.10.1.1"
}

#-----------
## Create int-interface
#-----------
resource "openstack_networking_router_interface_v2" "int-interface" {
  router_id = openstack_networking_router_v2.external-router.id
  subnet_id = openstack_networking_subnet_v2.int-subnet-1.id
}

#-----------
## Create key-pair admin-access
#-----------
resource "openstack_compute_keypair_v2" "admin-access" {
  name       = var.keypair_name
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCVGio3SyIFPiqrRVibXTWvirkNoJAfvzIeChl042Jt9cxJY/8pmrD7wKA4EyO4HQtYVfB2mmO6jx0LLUs/SM7blijM91HmDCspnDnouC8hcW1TCMlPdAXexlTuGuPmDZrfoJToylh/a+I/w3zE7zxGR8+yR6irg/kNKY6sQQAq2svTh5Y0hMyVEEGu9L4CnlZf1uMQfyOPvSdP0J5N1YjamBf9FKF7ABCFcYHgMS4c821jdI5x7D3JLV8pwk2LbG2mpv1GvMnmQ9N/EInv6fwByZ27cEf6K99MkdSLibIFDoW6PPvre2kX0wMZMoA0/WY37ZftzP0GMTYWi7dYaxrZ"
}

#-----------
## Create floatip_vm01-cirros
#-----------
#data "openstack_networking_subnet_ids_v2" "ext_subnets" {
#  network_id = openstack_networking_network_v2.ext-network.id
#}
#
#resource "openstack_networking_floatingip_v2" "floatip_vm01-cirros" {
#  pool       = openstack_networking_network_v2.ext-network.name
#  subnet_ids = data.openstack_networking_subnet_ids_v2.ext_subnets.ids
#}

#-----------
## Create image cirros 061
#-----------

resource "openstack_images_image_v2" "cirros_061" {
  name             = "cirros-0.6.1"
  image_source_url = "https://download.cirros-cloud.net/0.6.1/cirros-0.6.1-x86_64-disk.img"
  container_format = "bare"
  disk_format      = "qcow2"

  properties = {
    os_version          = "0.6.1"
    hw_qemu_guest_agent = "yes"
    os_distro           = "Others"
    usage_type          = "common"
    os_admin_user       = "root"
  }
}
#-----------
## Create flavor standard
#-----------

resource "openstack_compute_flavor_v2" "standard-2-2-6" {
  description = "Standard flavor for all VM"
  name        = "standard-2-2-6"
  vcpus       = "2"
  ram         = "2048"
  disk        = "3"
  swap        = "0"
  ephemeral   = "3"
  is_public   = "true"

  extra_specs = {
    ":architecture"             = "x86_architecture",
    ":category"                 = "compute_optimized",
    "quota:disk_total_iops_sec" = "2000",
    "hw:numa_nodes"             = "1",
    "hw:mem_page_size"          = "any"
  }
}

#-----------
## Create volume - vol-vm01
#-----------

#resource "openstack_blockstorage_volume_type_v3" "hdd-lvm" {
#  name        = "HDD-LVM"
#  description = "HDD LVM"
#  is_public = "true"
#  extra_specs = {
#    volume_backend_name = "hdd"
#  }
#}

resource "openstack_blockstorage_volume_v3" "vol-vm01" {
  name        = "vol-vm01"
  volume_type = "__DEFAULT__"
  size        = "3"
  image_id    = openstack_images_image_v2.cirros_061.id

  depends_on = [
    openstack_images_image_v2.cirros_061
  ]
}

#-----------
## Create Instance vm01-cirros
#-----------

resource "openstack_compute_instance_v2" "vm01-cirros" {
  name            = "vm01-cirros"
  flavor_id       = openstack_compute_flavor_v2.standard-2-2-6.id
  key_pair        = var.keypair_name
  security_groups = ["i_sg_1", "o_sg_1"]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.vol-vm01.id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  metadata = {
    env = "dev"
  }

  depends_on = [
    openstack_blockstorage_volume_v3.vol-vm01,
    openstack_networking_subnet_v2.int-subnet-1,
    openstack_compute_keypair_v2.admin-access
  ]

  network {
    name = "int-network"
  }
}

module "i_sg_1" {
  source      = "git::https://github.com/realscorp/tf-openstack-vkcs-secgroup.git?ref=v1.0.0"
  name        = "i_sg_1"
  description = "Group to access vm"
  rules = [{
    direction = "ingress"
    protocol  = "tcp"
    ports     = ["443", "22"]
    remote_ips = {
      "External LAN-RZN" = "192.168.2.0/23"
      "External LAN-MSK" = "192.168.4.0/23"
      "Internal LAN"     = "10.10.1.0/24"
    }
    },
    {
      direction = "ingress"
      protocol  = "udp"
      ports     = ["22"]
      remote_ips = {
        "External LAN-RZN" = "192.168.2.0/23"
        "External LAN-MSK" = "192.168.4.0/23"
        "Internal LAN"     = "10.10.1.0/24"
      }
    },
    {
      direction = "ingress"
      protocol  = "icmp"
      ports     = ["0"]
      remote_ips = {
        "External LAN-RZN" = "192.168.2.0/23"
        "External LAN-MSK" = "192.168.4.0/23"
        "Internal LAN"     = "10.10.1.0/24"
      }
  }]
}

module "o_sg_1" {
  source      = "git::https://github.com/realscorp/tf-openstack-vkcs-secgroup.git?ref=v1.0.0"
  name        = "o_sg_1"
  description = "Group to access vm"
  rules = [{
    direction = "egress"
    protocol  = "tcp"
    ports     = ["443"]
    remote_ips = {
      "External LAN-RZN" = "192.168.2.0/23"
      "External LAN-MSK" = "192.168.4.0/23"
      "Internal LAN"     = "10.10.1.0/24"
    }
    },
    {
      direction = "egress"
      protocol  = "icmp"
      ports     = ["0"]
      remote_ips = {
        "External LAN-RZN" = "192.168.2.0/23"
        "External LAN-MSK" = "192.168.4.0/23"
        "Internal LAN"     = "10.10.1.0/24"
      }
  }]
}

#-----------
## Create LB
#-----------
#
resource "openstack_networking_network_v2" "network_LB" {
  name           = "network_LB"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "subnet_LB" {
  name       = "subnet_LB"
  cidr       = "192.168.199.0/24"
  ip_version = 4
  network_id = openstack_networking_network_v2.network_LB.id
}

resource "openstack_lb_loadbalancer_v2" "loadbalancer_1" {
  name          = "loadbalancer_1"
  vip_subnet_id = openstack_networking_subnet_v2.subnet_LB.id
}

resource "openstack_lb_listener_v2" "listener_1" {
  name            = "listener_1"
  protocol        = "HTTP"
  protocol_port   = 443
  loadbalancer_id = openstack_lb_loadbalancer_v2.loadbalancer_1.id
}

resource "openstack_lb_pool_v2" "pool_1" {
  name            = "pool_1"
  protocol        = "HTTP"
  lb_method       = "ROUND_ROBIN"
  loadbalancer_id = openstack_lb_loadbalancer_v2.loadbalancer_1.id
}

resource "openstack_lb_l7policy_v2" "l7policy_1" {
  name             = "test"
  action           = "REDIRECT_TO_POOL"
  description      = "test l7 policy"
  position         = 1
  listener_id      = openstack_lb_listener_v2.listener_1.id
  redirect_pool_id = openstack_lb_pool_v2.pool_1.id
}




#data "vkcs_kubernetes_clustertemplate" "ct" {
#  version = "1.24"
#}
#
#resource "vkcs_kubernetes_cluster" "k8s-cluster" {
#  depends_on = [
#    vkcs_networking_router_interface.k8s,
#  ]
#
#  name                   = "k8s-cluster"
#  cluster_template_id    = data.vkcs_kubernetes_clustertemplate.ct.id
#  master_flavor          = data.vkcs_compute_flavor.k8s.id
#  master_count           = 1
#  network_id             = vkcs_networking_network.k8s.id
#  subnet_id              = vkcs_networking_subnet.k8s-subnetwork.id
#  floating_ip_enabled    = true
#  availability_zone      = "MS1"
#  ingress_floating_ip    = vkcs_networking_floatingip.ingressfip.address
#  loadbalancer_subnet_id = vkcs_networking_subnet.k8s-subnetwork.id
#
#  labels = {
#    calico_ipv4pool   = "10.222.0.0/16"
#  }
#}
#
#resource "vkcs_kubernetes_node_group" "groups" {
#  cluster_id = vkcs_kubernetes_cluster.k8s-cluster.id
#  flavor_id = data.vkcs_compute_flavor.k8s-node-group-flavor.id
#  node_count = 3
#  name       = "worker"
#  max_nodes  = 4
#  min_nodes  = 2
#
#  timeouts {
#    create = "30m"
#  }
#}
#
#
### loadbalancer
#
#resource "vkcs_networking_floatingip" "ingressfip" {
#  pool = data.vkcs_networking_network.extnet.name
#}
#
### database
#
#data "vkcs_compute_flavor" "db" {
#  name = "Standard-2-8-50"
#}
#
#### database
#resource "vkcs_db_instance" "db-instance" {
#  name        = "db-instance"
#  keypair     = var.keypair_name
#  flavor_id   = data.vkcs_compute_flavor.db.id
#  size        = 8
#  volume_type = "ceph-ssd"
#  disk_autoexpand {
#    autoexpand    = true
#    max_disk_size = 1000
#  }
#  depends_on = [
#    vkcs_kubernetes_cluster.k8s-cluster
#  ]
#
#  network {
#    uuid = vkcs_networking_network.k8s.id
#  }
#
#  datastore {
#    version = 14
#    type    = "postgresql"
#  }
#}
#
#resource "vkcs_db_database" "app" {
#  name       = "appdb"
#  dbms_id    = "${vkcs_db_instance.db-instance.id}"
#  charset    = "utf8"
#  depends_on = [
#    vkcs_db_instance.db-instance
#  ]
#}
#
## Генерим пароль для базы
#resource "random_string" "resource_code" {
#  length  = 10
#  special = false
#  numeric = true
#  upper   = false
#}
#
#resource "vkcs_db_user" "app_user" {
#  name     = "app_user"
#  password = "${random_string.resource_code.result}"
#  dbms_id  = "${vkcs_db_instance.db-instance.id}"
#
#  databases  = ["${vkcs_db_database.app.name}"]
#  depends_on = [
#    vkcs_db_database.app
#  ]
#}
#
########################
##  Output
#
#output "database" {
#  value = "db_password ${random_string.resource_code.result} ${vkcs_db_instance.db-instance.ip[0]}"
#}
#
#resource "local_file" "prod_env" {
#  content = templatefile("${path.module}/env.tpl",
#    {
#      host = vkcs_db_instance.db-instance.ip[0]
#    }
#  )
#  filename = "../../.github/prod_env"
#}
