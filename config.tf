terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = "0.177.0"
    }
  }
}

provider "yandex" {
  zone = "ru-central1-b"
}

resource "yandex_compute_disk" "boot-disk-1" {
  name     = "boot-disk-1"
  type     = "network-hdd"
  zone     = "ru-central1-b"
  size     = "20"
  image_id = "fd861t36p9dqjfrqm0g4"
}

resource "yandex_compute_disk" "boot-disk-2" {
  name     = "boot-disk-2"
  type     = "network-hdd"
  zone     = "ru-central1-b"
  size     = "20"
  image_id = "fd861t36p9dqjfrqm0g4"
}

data "yandex_vpc_subnet" "network1-b" {
  name = "default-ru-central1-b"
}

resource "yandex_compute_instance" "build" {
  name = "build"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk-1.id
  }

  scheduling_policy {
    preemptible = true
  }

  network_interface {
    subnet_id = data.yandex_vpc_subnet.network1-b.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.network_interface.0.nat_ip_address
    }

    inline = [
      "sudo apt update && sudo apt install -y default-jdk maven tomcat9",
      "cd /tmp && git clone https://github.com/boxfuse/boxfuse-sample-java-war-hello.git",
      "cd /tmp/boxfuse-sample-java-war-hello && mvn package",
      "sudo cp /tmp/boxfuse-sample-java-war-hello/target/hello-1.0.war /var/lib/tomcat9/webapps"
    ]
  }

  provisioner "local-exec" {
    command = "scp -r -o StrictHostKeyChecking=no ubuntu@${self.network_interface.0.nat_ip_address}:/var/lib/tomcat9/webapps/hello-1.0 /tmp/hello-1.0"
  }
}

resource "yandex_compute_instance" "prod" {
  name = "prod"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk-2.id
  }

  scheduling_policy {
    preemptible = true
  }

  network_interface {
    subnet_id = data.yandex_vpc_subnet.network1-b.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.network_interface.0.nat_ip_address
    }

    inline = [
      "sudo apt update && sudo apt install -y tomcat9",
      ]
  }

  provisioner "file" {
    source      = "/tmp/hello-1.0"
    destination = "/var/lib/tomcat9/webapps/hello-1.0"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.network_interface.0.nat_ip_address
    }
  }

  depends_on = [yandex_compute_instance.build]
}

output "internal_ip_address_build" {
  value = yandex_compute_instance.build.network_interface.0.ip_address
}

output "external_ip_address_build" {
  value = yandex_compute_instance.build.network_interface.0.nat_ip_address
}

output "internal_ip_address_prod" {
  value = yandex_compute_instance.prod.network_interface.0.ip_address
}

output "external_ip_address_prod" {
  value = yandex_compute_instance.prod.network_interface.0.nat_ip_address
}