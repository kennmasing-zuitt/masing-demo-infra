resource "digitalocean_droplet" "main" {
  name       = var.droplet_name
  region     = var.region
  size       = var.droplet_size
  image      = "ubuntu-24-04-x64"
  ssh_keys   = var.do_ssh_keys
  monitoring = true
  user_data = templatefile("${path.module}/files/cloud-init.yaml.tftpl", {
    hostname           = var.droplet_name
    kenneth_keys       = var.kenneth_ssh_keys
    hermes_keys        = var.hermes_ssh_keys
    tailscale_auth_key = var.tailscale_auth_key
  })

  lifecycle {
    # First boot only. Later changes go through the deploy step; a new Tailscale key must not rebuild the droplet.
    ignore_changes = [user_data]
  }
}

# The address the A records point to; it survives a droplet rebuild
resource "digitalocean_reserved_ip" "main" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "main" {
  ip_address = digitalocean_reserved_ip.main.ip_address
  droplet_id = digitalocean_droplet.main.id
}

# Web only. No SSH rule: SSH is reachable over Tailscale alone.
resource "digitalocean_firewall" "main" {
  name        = var.droplet_name
  droplet_ids = [digitalocean_droplet.main.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
