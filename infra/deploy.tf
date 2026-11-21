locals {
  images = { for name, tag in var.image_tags : name => "${var.image_registry}/${name}:${tag}" }

  apps = toset([for f in fileset("${path.module}/apps", "*/compose.yaml.tftpl") : dirname(f)])

  # Hand-written proxy configs, copied verbatim
  custom_conf = { for f in fileset("${path.module}/proxy/conf.d", "*.conf") : f => file("${path.module}/proxy/conf.d/${f}") }

  # Generated simple sites
  simple_conf = {
    for name, s in var.simple_sites : "${name}.conf" => templatefile("${path.module}/files/site.conf.tftpl", {
      host      = s.host
      upstream  = s.upstream
      cert_name = var.cert_name
    })
  }

  conf = merge(local.custom_conf, local.simple_conf)

  # Every host the proxy serves; the certificate must list all of them
  cert_hosts = sort(distinct(flatten([
    for c in values(local.conf) : [
      for m in regexall("(?m)^\\s*server_name\\s+([^;]+);", c) : split(" ", trimspace(m[0]))
    ]
  ])))

  # Files copied to the droplet: absolute path => content
  files = merge(
    { "/srv/proxy/compose.yaml" = file("${path.module}/proxy/compose.yaml") },
    { for f, c in local.conf : "/srv/proxy/conf.d/${f}" => c },
    { for a in local.apps : "/srv/apps/${a}/compose.yaml" => templatefile("${path.module}/apps/${a}/compose.yaml.tftpl", { images = local.images }) },
    {
      "/srv/bin/certs.sh" = templatefile("${path.module}/files/certs.sh.tftpl", {
        cert_name     = var.cert_name
        hosts         = local.cert_hosts
        public_ip     = digitalocean_reserved_ip.main.ip_address
        certbot_email = var.certbot_email
      })
      "/etc/systemd/system/zuitt-demo-certs.service" = file("${path.module}/files/certs.service")
      "/etc/systemd/system/zuitt-demo-certs.timer"   = file("${path.module}/files/certs.timer")
    },
  )

  # App secrets: secrets/<app>.env on the Terraform machine (gitignored) => /srv/apps/<app>/.env
  secret_files = {
    for f in fileset("${path.root}/../secrets", "*.env") :
    "/srv/apps/${trimsuffix(f, ".env")}/.env" => file("${path.root}/../secrets/${f}")
  }
}

resource "terraform_data" "deploy" {
  lifecycle {
    precondition {
      condition     = alltrue([for p in keys(local.secret_files) : contains([for a in local.apps : "/srv/apps/${a}/.env"], p)])
      error_message = "Every secrets/<name>.env must match an app folder under infra/apps/."
    }
  }

  # Re-run when the droplet, a file or a secret changes (secrets only as a hash)
  triggers_replace = [
    digitalocean_droplet.main.id,
    sha1(jsonencode(local.files)),
    sha1(jsonencode(local.secret_files)),
  ]

  depends_on = [
    digitalocean_reserved_ip_assignment.main,
    digitalocean_firewall.main,
  ]

  connection {
    type        = "ssh"
    host        = var.deploy_host
    user        = "hermes"
    private_key = file(pathexpand(var.deploy_ssh_key))
    timeout     = "10m" # a new droplet needs a minute or two to join the tailnet
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo cloud-init status --wait >/dev/null || true",
      "sudo docker version >/dev/null",
      "install -d -m 700 ~/.deploy",
    ]
  }

  provisioner "file" {
    content     = jsonencode(merge(local.files, local.secret_files))
    destination = "/home/hermes/.deploy/bundle.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "trap 'rm -f ~/.deploy/bundle.json' EXIT",
      "chmod 600 ~/.deploy/bundle.json",
      "sudo python3 - ~/.deploy/bundle.json <<'PY'\n${file("${path.module}/files/unpack.py")}\nPY",
      "sudo docker network inspect web >/dev/null 2>&1 || sudo docker network create web",
      "for a in ${join(" ", local.apps)}; do sudo docker compose -f /srv/apps/$a/compose.yaml pull --quiet && sudo docker compose -f /srv/apps/$a/compose.yaml up -d --remove-orphans --wait --wait-timeout 180; done",
      "sudo /srv/bin/certs.sh bootstrap",
      "sudo docker compose -f /srv/proxy/compose.yaml up -d --remove-orphans",
      # conf.d is a mounted folder: Compose doesn't restart Nginx when only those files change
      "sudo docker compose -f /srv/proxy/compose.yaml exec -T nginx nginx -t",
      "sudo docker compose -f /srv/proxy/compose.yaml exec -T nginx nginx -s reload",
      "sudo systemctl daemon-reload && sudo systemctl enable --now zuitt-demo-certs.timer",
      "sudo /srv/bin/certs.sh",
      "sudo docker image prune -af --filter until=24h >/dev/null",
    ]
  }
}
