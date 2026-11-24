variable "droplet_name" {
  description = "Droplet name, also its Tailscale hostname (deploy_host)"
  type        = string
}

variable "region" {
  type = string
}

variable "droplet_size" {
  type = string
}

variable "do_ssh_keys" {
  description = "DigitalOcean SSH key IDs/fingerprints for root (root login is disabled; this only stops DO from emailing a root password)"
  type        = list(string)
}

variable "kenneth_ssh_keys" {
  description = "Public keys for the kenneth user (sudo + docker)"
  type        = list(string)
}

variable "hermes_ssh_keys" {
  description = "Public keys for the hermes user (sudo + docker); include the deploy key of the machine running Terraform"
  type        = list(string)
}

variable "deploy_host" {
  description = "Tailnet name the deploy step SSHes to (there is no public SSH)"
  type        = string
}

variable "deploy_ssh_key" {
  description = "Private key on the Terraform machine matching one of hermes_ssh_keys"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "tailscale_auth_key" {
  description = "From TF_VAR_tailscale_auth_key; only read when the droplet is created (user_data is ignored afterwards)"
  type        = string
  default     = ""
  sensitive   = true
  nullable    = false
}

variable "image_registry" {
  type    = string
  default = "ghcr.io/kennmasing-zuitt"
}

variable "image_tags" {
  description = "GHCR image name => tag, e.g. sha-1a2b3c4"
  type        = map(string)
}

variable "simple_sites" {
  description = "Sites rendered from files/site.conf.tftpl into conf.d/<key>.conf. Sites with custom routing go in proxy/conf.d/ instead."
  type = map(object({
    host     = string
    upstream = string # container alias:port on the web network
  }))
}

variable "cert_name" {
  description = "Let's Encrypt certificate covering every server_name; expanded automatically when a site is added"
  type        = string
}

variable "certbot_email" {
  type = string
}

variable "app_env_files" {
  description = "Each app's runtime .env, keyed by file name (<app>.env => /srv/apps/<app>/.env). scripts/tf.sh loads it from the secret masings-tf-masing-demo-infra-apps-env."
  type        = map(string)
  sensitive   = true
}
