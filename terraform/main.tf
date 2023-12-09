terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = ".\\key.json"
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "yandex_test_vpc" {}

resource "yandex_vpc_subnet" "yandex_test_vpc_subnet" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.yandex_test_vpc.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

resource "yandex_container_registry" "yandex_test_registry" {
  name = "catgpt"
}

locals {
  folder_id = "b1gjeesvmfrpc9r3shrd"
  service-accounts = toset([
    "catgpt-sa",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}

resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_compute_instance" "catgpt-1" {
    count              = 2
    name               = "catgpt-1-${count.index + 1}"
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      subnet_id = "${yandex_vpc_subnet.yandex_test_vpc_subnet.id}"
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = file("${path.module}/docker-compose.yaml")
      ssh-keys  = "ubuntu:${file("C:\\Users\\aliak\\.ssh\\id_rsa.pub")}"
    }
}

resource "yandex_lb_target_group" "catGpt_group" {
  name      = "catGpt_group"

  dynamic "target" {
    for_each = yandex_compute_instance.catgpt-1
    content {
      subnet_id = yandex_compute_instance.catgpt-1[target.key].network_interface[0].subnet_id
      address   = yandex_compute_instance.catgpt-1[target.key].network_interface[0].nat_ip
    }
  }
}

resource "yandex_lb_network_load_balancer" "catGpt_load_balancer" {
  name               = "catGptLoadBalancer"
  type               = "internal"
  deletion_protection = false

  listener {
    name = "http-listener"
    port = 80

    internal_address_spec {
      subnet_id   = yandex_vpc_subnet.yandex_test_vpc_subnet.id
      ip_version  = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.catGpt_group.id

    healthcheck {
      name = "http-healthcheck"

      http_options {
        port = 8080
        path = "/ping"  
      }
    }
  }
}