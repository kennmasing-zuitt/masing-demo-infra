output "reserved_ip" {
  value = digitalocean_reserved_ip.main.ip_address
}

output "a_records" {
  description = "Namecheap: one A record per host, value = reserved_ip"
  value       = local.cert_hosts
}

output "ssh" {
  value = "ssh hermes@${var.deploy_host}  (Tailscale only)"
}
