variable "node_count" {}

variable "connections" {
  type = list
}

variable "hostnames" {
  type = list
}

variable "vpn_unit" {
  type = string
}

variable "vpn_ips" {
  type = list
}

locals {
  etcd_hostnames = slice(var.hostnames, 0, var.node_count)
  etcd_vpn_ips   = slice(var.vpn_ips, 0, var.node_count)
}

variable "etcd_version" {
  default = "v3.4.13"
}

resource "null_resource" "etcd" {
  count = var.node_count

  triggers = {
    template = join("", data.template_file.etcd-service.*.rendered)
  }

  connection {
    host  = element(var.connections, count.index)
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "${data.template_file.install.rendered}"
    ]
  }

  provisioner "file" {
    content     = element(data.template_file.etcd-service.*.rendered, count.index)
    destination = "/etc/systemd/system/etcd.service"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl is-enabled etcd.service || systemctl enable etcd.service",
      "systemctl daemon-reload",
      # etcd needs connectivity between nodes (e.g. via wireguard private IPs: `vpn_ips`) or else we
      # get startup errors like `listen tcp 10.0.1.2:2380: bind: cannot assign requested address`.
      # Therefore let systemd restart the service a few more times if necessary, and wait until it is running.
      "systemctl restart etcd.service || true",
      "for n in $(seq 1 20); do if systemctl is-active etcd.service; then exit 0; fi; sleep 5; done; echo 'etcd failed to start, latest status:'; systemctl --no-pager status etcd.service; echo; exit 1",
    ]
  }
}

data "template_file" "etcd-service" {
  count    = var.node_count
  template = file("${path.module}/templates/etcd.service")

  # Assume IPv4 if address contains a dot, IPv6 otherwise
  vars = {
    hostname              = element(local.etcd_hostnames, count.index)
    intial_cluster        = "${join(",", formatlist("%s=http://%s%s%s:2380", local.etcd_hostnames, can(regex("\\.", element(local.etcd_vpn_ips, 0))) ? "" : "[", local.etcd_vpn_ips, can(regex("\\.", element(local.etcd_vpn_ips, 0))) ? "" : "]"))}"
    listen_client_urls    = "http://${can(regex("\\.", element(local.etcd_vpn_ips, count.index))) ? "" : "["}${element(local.etcd_vpn_ips, count.index)}${can(regex("\\.", element(local.etcd_vpn_ips, count.index))) ? "" : "]"}:2379"
    advertise_client_urls = "http://${can(regex("\\.", element(local.etcd_vpn_ips, count.index))) ? "" : "["}${element(local.etcd_vpn_ips, count.index)}${can(regex("\\.", element(local.etcd_vpn_ips, count.index))) ? "" : "]"}:2379"
    listen_peer_urls      = "http://${can(regex("\\.", element(local.etcd_vpn_ips, count.index))) ? "" : "["}${element(local.etcd_vpn_ips, count.index)}${can(regex("\\.", element(local.etcd_vpn_ips, count.index))) ? "" : "]"}:2380"
    vpn_unit              = var.vpn_unit
  }
}

data "template_file" "install" {
  template = file("${path.module}/scripts/install.sh")

  vars = {
    version = var.etcd_version
  }
}

data "null_data_source" "endpoints" {
  depends_on = [null_resource.etcd]

  # Assume IPv4 if address contains a dot, IPv6 otherwise
  inputs = {
    list = "${join(",", formatlist("http://%s%s%s:2379", can(regex("\\.", element(local.etcd_vpn_ips, 0))) ? "" : "[", local.etcd_vpn_ips, can(regex("\\.", element(local.etcd_vpn_ips, 0))) ? "" : "]"))}"
  }
}

output "endpoints" {
  value = "${split(",", data.null_data_source.endpoints.outputs["list"])}"
}
