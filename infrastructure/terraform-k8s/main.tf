terraform {
  required_providers {
    vkcs = {
      source = "vk-cs/vkcs"
    }
  }
}

data "vkcs_kubernetes_clustertemplate" "ct" {
  version = "1.27"
}

resource "vkcs_kubernetes_cluster" "k8s-cluster" {
  depends_on = [
    vkcs_networking_router_interface.k8s,
  ]

  name                   = "k8s-cluster"
  cluster_template_id    = data.vkcs_kubernetes_clustertemplate.ct.id
  master_flavor          = data.vkcs_compute_flavor.k8s.id
  master_count           = 1
  network_id             = vkcs_networking_network.k8s.id
  subnet_id              = vkcs_networking_subnet.k8s-subnetwork.id
  floating_ip_enabled    = true
  availability_zone      = "MS1"
  ingress_floating_ip    = vkcs_networking_floatingip.ingressfip.address
  loadbalancer_subnet_id = vkcs_networking_subnet.k8s-subnetwork.id

  labels = {
    calico_ipv4pool = "10.222.0.0/16"
  }
}

resource "vkcs_kubernetes_node_group" "groups" {
  cluster_id = vkcs_kubernetes_cluster.k8s-cluster.id
  flavor_id  = data.vkcs_compute_flavor.k8s-node-group-flavor.id
  node_count = 2
  name       = "worker"
  max_nodes  = 3
  min_nodes  = 2

  timeouts {
    create = "30m"
  }
}


## loadbalancer

resource "vkcs_networking_floatingip" "ingressfip" {
  pool = data.vkcs_networking_network.extnet.name
}

## database
#
data "vkcs_compute_flavor" "db" {
  name = "STD2-2-8"
}

### database
resource "vkcs_db_instance" "db-instance" {
  name        = "db-instance"
  keypair     = var.keypair_name
  flavor_id   = data.vkcs_compute_flavor.db.id
  size        = 8
  volume_type = "ceph-ssd"
  disk_autoexpand {
    autoexpand    = true
    max_disk_size = 1000
  }
  timeouts {
    create = "30m"
  }
  depends_on = [
    vkcs_kubernetes_cluster.k8s-cluster
  ]

  network {
    uuid = vkcs_networking_network.k8s.id
  }

  datastore {
    version = 14
    type    = "postgresql"
  }
  wal_volume {
    size        = 4
    volume_type = "ceph-ssd"
  }
}

# Генерим пароль для базы
resource "random_string" "resource_code" {
  length  = 16
  special = false
  numeric = true
  upper   = true
}

resource "vkcs_db_database" "app" {
  name    = "appdb"
  dbms_id = vkcs_db_instance.db-instance.id
  charset = "utf8"
}

resource "vkcs_db_user" "app_user" {
  name      = "app_user"
  password  = random_string.resource_code.result
  dbms_id   = vkcs_db_instance.db-instance.id
  databases = [vkcs_db_database.app.name]
}

#######################
#  Output

#output "database" {
#  value = "db_password ${random_string.resource_code.result} ${vkcs_db_instance.db-instance.ip[0]}"
#}

resource "local_file" "prod_env" {
  content = templatefile("${path.module}/env.tpl",
    {
      host = vkcs_db_instance.db-instance.ip[0]
    }
  )
  filename = "../../.github/prod_env"
}
