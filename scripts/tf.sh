#!/usr/bin/env bash
# Run Terraform for zuitt-demo with the right credentials.
#   scripts/tf.sh plan|apply|output|state|... [args...]
#
# .env (repo root, gitignored):
#   DIGITALOCEAN_TOKEN=...            zuitt-demo's own token
#   TF_VAR_tailscale_auth_key=...     only while creating the droplet; delete it afterwards
# secrets/<app>.env (gitignored): each app's runtime .env, copied to /srv/apps/<app>/.env
# State: GCS backend in infra/versions.tf, read and written with the masings-tf-state key
# (masings repo README, "Rebuilding agentic-loop")
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

key="$HOME/.config/masings-secrets/masings-tf-state.json"
[ -f "$key" ] || { echo "Missing $key (Terraform state key; masings README \"Rebuilding agentic-loop\")"; exit 1; }
# Only this key may reach the state: drop anything that would override it or redirect the backend
unset GOOGLE_CREDENTIALS GOOGLE_OAUTH_ACCESS_TOKEN GOOGLE_APPLICATION_CREDENTIALS \
    GOOGLE_BACKEND_IMPERSONATE_SERVICE_ACCOUNT GOOGLE_IMPERSONATE_SERVICE_ACCOUNT \
    GOOGLE_BACKEND_STORAGE_CUSTOM_ENDPOINT GOOGLE_STORAGE_CUSTOM_ENDPOINT GOOGLE_ENCRYPTION_KEY
export GOOGLE_BACKEND_CREDENTIALS="$key"
# A non-empty local state file means the state was never moved to the bucket: stop before init,
# which would create an empty state in the bucket before refusing to migrate
[ ! -s "$dir/terraform.tfstate" ] || { echo "$dir/terraform.tfstate holds local state: move it to the bucket first; tf.sh never moves state"; exit 1; }

# Init on every run: a no-op when the backend matches, a hard stop when it changed (a local state
# file is refused above). Never pass -reconfigure or -migrate-state here: moving state is a reviewed step.
terraform -chdir="$dir" init -input=false >/dev/null

cmd="${1:?usage: scripts/tf.sh <terraform command> [args...]}"
if [ "$cmd" = plan ] || [ "$cmd" = apply ]; then
    # A new droplet can only be reached by joining the tailnet on first boot
    resources=$(terraform -chdir="$dir" state list) || { echo "Cannot read the state (error above)"; exit 1; }
    if ! grep -qx digitalocean_droplet.main <<<"$resources" && [ -z "${TF_VAR_tailscale_auth_key:-}" ]; then
        echo "The droplet will be created: set TF_VAR_tailscale_auth_key in .env first (single-use, tagged key)"
        exit 1
    fi
fi
exec terraform -chdir="$dir" "$@"
