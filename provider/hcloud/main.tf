variable "token" {}

variable "hosts" {
  default = 0
}

variable "hostname_format" {
  type = string
}

variable "location" {
  type = string
}

variable "type" {
  type = string
}

variable "image" {
  type = string
}

variable "ssh_keys" {
  type = list(string)
}

provider "hcloud" {
  token = var.token
}

variable "apt_packages" {
  type    = list(string)
  default = []
}

variable "ipv4_enabled" {
  type    = bool
  default = true
}

variable "ipv6_enabled" {
  type    = bool
  default = true
}

resource "hcloud_server" "host" {
  name        = format(var.hostname_format, count.index + 1)
  location    = var.location
  image       = var.image
  server_type = var.type
  ssh_keys    = var.ssh_keys
  public_net {
    ipv4_enabled = var.ipv4_enabled
    ipv6_enabled = var.ipv6_enabled
  }

  count = var.hosts

  connection {
    user    = "root"
    type    = "ssh"
    timeout = "2m"
    host    = coalesce(self.ipv6_address, self.ipv4_address)
  }

  provisioner "remote-exec" {
    inline = [
      "while fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do sleep 1; done",
      "apt-get update",
      "apt-get install -yq ufw ${join(" ", var.apt_packages)}",
    ]
  }
}

# resource "hcloud_volume" "volume" {
#   name      = format(var.hostname_format, count.index + 1)
#   size      = 10
#   server_id = element(hcloud_server.host.*.id, count.index)
#   automount = false

#   count = var.hosts
# }

output "hostnames" {
  value = hcloud_server.host.*.name
}

output "public_ips" {
  value = var.ipv4_enabled ? hcloud_server.host.*.ipv4_address : hcloud_server.host.*.ipv6_address
}

output "private_ips" {
  value = var.ipv4_enabled ? hcloud_server.host.*.ipv4_address : hcloud_server.host.*.ipv6_address
}

output "private_network_interface" {
  value = "eth0"
}
