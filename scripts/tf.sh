#!/usr/bin/env bash
# Run Terraform for zuitt-demo with the right credentials.
#   scripts/tf.sh plan|apply|output|state|... [args...]
#
# .env (repo root, gitignored):
#   DIGITALOCEAN_TOKEN=...            zuitt-demo's own token
#   TF_VAR_tailscale_auth_key=...     only while creating the droplet; delete it afterwards
# secrets/<app>.env (gitignored): each app's runtime .env, copied to /srv/apps/<app>/.env
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/infra"

[ -f "$root/.env" ] || { echo "Missing $root/.env (DIGITALOCEAN_TOKEN)"; exit 1; }
# Never fall back to another project's token
unset DIGITALOCEAN_ACCESS_TOKEN DIGITALOCEAN_TOKEN TF_VAR_tailscale_auth_key
set -a
# shellcheck disable=SC1091
. "$root/.env"
set +a
[ -n "${DIGITALOCEAN_TOKEN:-}" ] || { echo ".env must set DIGITALOCEAN_TOKEN"; exit 1; }

[ -d "$dir/.terraform" ] || terraform -chdir="$dir" init -input=false >/dev/null

cmd="${1:?usage: scripts/tf.sh <terraform command> [args...]}"
if [ "$cmd" = plan ] || [ "$cmd" = apply ]; then
    # A new droplet can only be reached by joining the tailnet on first boot
    if ! terraform -chdir="$dir" state list 2>/dev/null | grep -qx digitalocean_droplet.main \
        && [ -z "${TF_VAR_tailscale_auth_key:-}" ]; then
        echo "The droplet will be created: set TF_VAR_tailscale_auth_key in .env first (single-use, tagged key)"
        exit 1
    fi
fi
exec terraform -chdir="$dir" "$@"
