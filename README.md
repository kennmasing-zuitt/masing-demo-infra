# masing-demo-infra

Terraform for the masing-demo droplet (sgp1): one Nginx proxy container in front of
Docker Compose apps, images from GHCR, SSH over Tailscale only.

Runs on agentic-loop (user `masings`, `~/projects/masing-demo-infra`). The state lives in the GCS
bucket `gs://masings-tfstate` (prefix `masing-demo-infra/infra`); `scripts/tf.sh` reads it with the
`masings-tf-state` key in `~/.config/masings-secrets/`. Credentials come from GCP Secret Manager
(project `masings-secrets`), read with the `masings-tf-reader` key; nothing is kept in files:

- `masings-tf-masing-demo-infra-env`: `DIGITALOCEAN_TOKEN=...` (+ `TF_VAR_tailscale_auth_key=...`
  only while creating the droplet; remove it afterwards). Only these two keys, token values;
  `scripts/tf.sh` refuses the secret on any other line. Change them from the masings repo with your
  own gcloud login, never by typing values into a gcloud command: `infra/gcp/secrets.sh set
  masings-tf-masing-demo-infra-env:DIGITALOCEAN_TOKEN` (new token) or `infra/gcp/secrets.sh add
  masings-tf-masing-demo-infra-env:TF_VAR_tailscale_auth_key` (before creating the droplet); see the
  masings runbook `docs/runbooks/secrets.md`. Removing the Tailscale line again has no subcommand
  yet: ask Hermes Cloud for the steps.
- `masings-tf-masing-demo-infra-apps-env`: each app's runtime `.env` as a JSON map
  `{"<app>.env": "<content>"}`, copied to `/srv/apps/<app>/.env`

Changing them and rebuilding the box: masings repo README, "Credentials" and "Rebuilding
agentic-loop". `scripts/tf.sh` needs `gcloud` and `jq` on `PATH`.

```
infra/
  main.tf, deploy.tf      droplet + reserved IP + firewall; deploy step over SSH (Tailscale)
  terraform.tfvars        sizes, keys, image tags, simple sites
  apps/<app>/compose.yaml.tftpl   one Compose project per app -> /srv/apps/<app>/
  proxy/compose.yaml      Nginx + certbot -> /srv/proxy/
  proxy/conf.d/*.conf     hand-written site configs, copied verbatim
  files/site.conf.tftpl   template for simple sites (simple_sites in terraform.tfvars)
  files/certs.sh.tftpl    one Let's Encrypt cert for every server_name, expanded when a site is added
```

## Add a site
1. Publish its image to GHCR (copy `.github/workflows/publish.yml` from an existing app repo).
2. Add `infra/apps/<app>/compose.yaml.tftpl` joining the external `web` network with an alias.
3. Simple proxy: an entry in `simple_sites`. Custom routing: a file in `infra/proxy/conf.d/`.
4. Add its tag to `image_tags`, then `scripts/tf.sh plan -out=tfplan` and `scripts/tf.sh apply tfplan`.
5. Add the A record at Namecheap (value: `terraform output reserved_ip`). The certificate expands
   by itself once the name resolves (timer twice a day, or `sudo /srv/bin/certs.sh`).
