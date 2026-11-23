# zuitt-demo-infra

Terraform for the zuitt-demo droplet (sgp1): one Nginx proxy container in front of
Docker Compose apps, images from GHCR, SSH over Tailscale only.

Runs on agentic-loop (user `masings`, `~/projects/zuitt-demo-infra`). The state lives in the GCS
bucket `gs://masings-tfstate` (prefix `zuitt-demo-infra/infra`); `scripts/tf.sh` reads it with the
`masings-tf-state` key in `~/.config/masings-secrets/`. Credentials come from GCP Secret Manager
(project `masings-secrets`), read with the `masings-tf-reader` key; nothing is kept in files:

- `masings-tf-zuitt-demo-infra-env`: `DIGITALOCEAN_TOKEN=...` (+ `TF_VAR_tailscale_auth_key=...`
  only while creating the droplet; remove it afterwards). Only these two keys, token values;
  `scripts/tf.sh` refuses the secret on any other line. To add or remove the Tailscale line, add a
  whole new version with your own gcloud login (`gcloud secrets versions add
  masings-tf-zuitt-demo-infra-env --project=masings-secrets --data-file=-`, type both lines, Ctrl-D)
  and destroy the old version once the droplet has joined.
- `masings-tf-zuitt-demo-infra-apps-env`: each app's runtime `.env` as a JSON map
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
