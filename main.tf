# -----------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------

variable "docker_host" {
  default = "unix:///var/run/docker.sock"
}

variable "splunk_version" {
  default = "latest"
  # default = "8.2.6"
  # default = "8.0.4.1"
  # default = "8.1"
}

variable "telegraf_version" {
  default = "1.12.6"
  # default = "1.20"
}

variable "vault_version" {
  default = "1.8.4"
}

variable "fluentd_splunk_hec_version" {
  default = "0.0.2"
}

# -----------------------------------------------------------------------
# Global configuration
# -----------------------------------------------------------------------

terraform {
  backend "local" {
    path = ".terraform/terraform.tfstate"
  }
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------
# Custom network
# -----------------------------------------------------------------------
resource "docker_network" "lvm_network" {
  name       = "lvm-network"
  attachable = true
  ipam_config { subnet = "10.42.10.0/24" }
}

# -----------------------------------------------------------------------
# Splunk resources
# -----------------------------------------------------------------------

resource "docker_image" "splunk" {
  name         = "splunk/splunk:${var.splunk_version}"
  keep_locally = true
}

resource "docker_container" "splunk" {
  name  = "lvm-splunk"
  image = docker_image.splunk.latest
  env   = ["SPLUNK_START_ARGS=--accept-license", "SPLUNK_PASSWORD=lvm-password", "SPLUNK_DB=/var/lib/splunk"]

  upload {
    content = (file("${path.cwd}/config/default.yml"))
    file    = "/tmp/defaults/default.yml"
  }

  ports {
    internal = "8443"
    external = "8443"
    protocol = "tcp"
  }

  networks_advanced {
    name         = "lvm-network"
    ipv4_address = "10.42.10.100"
  }
}

# -----------------------------------------------------------------------
# Fluentd resources
# Uses @brianshumate's fluentd-splunk-hec image
# https://github.com/brianshumate/fluentd-splunk-hec
# -----------------------------------------------------------------------

resource "docker_image" "fluentd_splunk_hec" {
  name         = "brianshumate/fluentd-splunk-hec:${var.fluentd_splunk_hec_version}"
  keep_locally = true
}

resource "docker_container" "fluentd" {
  name  = "lvm-fluentd"
  image = docker_image.fluentd_splunk_hec.latest
  volumes {
    host_path      = "${path.cwd}/vault-audit-log"
    container_path = "/vault/logs"
  }
  volumes {
    host_path      = "${path.cwd}/config/fluent.conf"
    container_path = "/fluentd/etc/fluent.conf"
  }
  networks_advanced {
    name         = "lvm-network"
    ipv4_address = "10.42.10.101"
  }
}

# -----------------------------------------------------------------------
# Telegraf resources
# -----------------------------------------------------------------------

resource "docker_image" "telegraf" {
  name         = "telegraf:${var.telegraf_version}"
  keep_locally = true
}

resource "docker_container" "telegraf" {
  name  = "lvm-telegraf"
  image = docker_image.telegraf.latest
  networks_advanced {
    name         = "lvm-network"
    ipv4_address = "10.42.10.102"
  }
  upload {
    content = templatefile("${path.cwd}/config/telegraf.conf", { test = "var" })
    file    = "/etc/telegraf/telegraf.conf"
  }
}

# -----------------------------------------------------------------------
# Vault data and resources
# -----------------------------------------------------------------------

resource "docker_image" "vault" {
  name         = "vault:${var.vault_version}"
  keep_locally = true
}

resource "docker_container" "vault" {
  name     = "lvm-vault"
  image    = docker_image.vault.latest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://127.0.0.1:8200"]
  command  = ["vault", "server", "-log-level=trace", "-config=/vault/config"]
  hostname = "lvm-vault"
  must_run = true
  capabilities {
    add = ["IPC_LOCK"]
  }
  healthcheck {
    test         = ["CMD", "vault", "status"]
    interval     = "10s"
    timeout      = "2s"
    start_period = "10s"
    retries      = 2
  }
  networks_advanced {
    name         = "lvm-network"
    ipv4_address = "10.42.10.103"
  }
  ports {
    internal = "8200"
    external = "8200"
    protocol = "tcp"
  }
  upload {
    content = templatefile("${path.cwd}/config/vault.hcl", { test = "var" })
    file    = "/vault/config/main.hcl"
  }
  volumes {
    host_path      = "${path.cwd}/vault-audit-log"
    container_path = "/vault/logs"
  }
}
