#!/usr/bin/env bash
# Run Terraform for masing-demo with the right credentials.
#   scripts/tf.sh plan|apply|output|state|... [args...]
#
# Credentials come only from GCP Secret Manager (project masings-secrets), read with the
# masings-tf-reader key in ~/.config/masings-secrets/; never from files or your environment.
# Change them with the masings repo's infra/gcp/secrets.sh (masings README "Credentials"):
#   masings-tf-masing-demo-infra-env       DIGITALOCEAN_TOKEN=... (masing-demo's own token), plus
#                                         TF_VAR_tailscale_auth_key=... only while creating the droplet
#   masings-tf-masing-demo-infra-apps-env  JSON map {"<app>.env": "<content>"}: each app's runtime
#                                         .env, copied to /srv/apps/<app>/.env
# State: GCS backend in infra/versions.tf, read and written with the masings-tf-state key
# (masings repo README, "Rebuilding agentic-loop")
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/infra"
keys="$HOME/.config/masings-secrets"

die() { echo "$*" >&2; exit 1; }

# Local checks first, before any network call
cmd="${1:?usage: scripts/tf.sh <terraform command> [args...]}"
shift
command -v gcloud >/dev/null || die "gcloud is not installed or not on PATH (masings README \"Rebuilding agentic-loop\")"
command -v jq >/dev/null || die "jq is not installed"
[ -f "$keys/masings-tf-reader.json" ] || die "Missing $keys/masings-tf-reader.json (masings README \"Rebuilding agentic-loop\")"
[ -f "$keys/masings-tf-state.json" ] || die "Missing $keys/masings-tf-state.json (Terraform state key; masings README \"Rebuilding agentic-loop\")"
# A non-empty local state file means the state was never moved to the bucket: stop before init,
# which would create an empty state in the bucket before refusing to migrate
[ ! -s "$dir/terraform.tfstate" ] || die "$dir/terraform.tfstate holds local state: move it to the bucket first; tf.sh never moves state"

# Print the latest version of one secret, read with the reader key only: gcloud settings that
# could pick another identity or endpoint are dropped. Same as read_secret in the masings repo's
# scripts/secrets-env.sh: keep the two in step.
read_secret() {
    (
        unset CLOUDSDK_AUTH_ACCESS_TOKEN_FILE CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT CLOUDSDK_CORE_ACCOUNT \
            CLOUDSDK_API_ENDPOINT_OVERRIDES_SECRETMANAGER
        CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="$keys/masings-tf-reader.json" \
            gcloud secrets versions access latest --project=masings-secrets --secret="$1" --quiet
    )
}

# Print one secret; stop when it can't be read or is empty
fetch() {
    local v
    v="$(read_secret "$1")" || die "Cannot read secret $1 (gcloud error above)"
    [ -n "$v" ] || die "Secret $1 is empty"
    printf '%s' "$v"
}

# Never fall back to another project's token or to settings already in the environment
unset DIGITALOCEAN_ACCESS_TOKEN DIGITALOCEAN_TOKEN
for v in ${!TF_VAR_@}; do unset "$v"; done

env="$(fetch masings-tf-masing-demo-infra-env)"
# Only the keys this secret may hold, each with a non-empty token value; anything else is refused before
# anything is exported, and nothing is ever evaluated (so a line can't run a command or set
# TF_CLI_ARGS_*, BASH_ENV, LD_PRELOAD ...). Same rules as the masings repo's scripts/secrets-env.sh
# for this secret: keep the two in step.
# Character sets spelled out, not ranges: ranges follow the locale (en_US.UTF-8 matches é)
blank_re=$'^[ \t]*(#.*)?$'
line_re="^(DIGITALOCEAN_TOKEN|TF_VAR_tailscale_auth_key)=([ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:/+=@-]+)\$"
names=() values=() n=0
while IFS= read -r line; do
    n=$((n + 1))
    [[ "$line" =~ $blank_re ]] && continue
    [[ "$line" =~ $line_re ]] \
        || die "Secret masings-tf-masing-demo-infra-env, line $n: not an allowed KEY=token"
    [[ " ${names[*]-} " != *" ${BASH_REMATCH[1]} "* ]] || die "Secret masings-tf-masing-demo-infra-env, line $n: ${BASH_REMATCH[1]} set twice"
    names+=("${BASH_REMATCH[1]}") values+=("${BASH_REMATCH[2]}")
done < <(printf '%s\n' "$env")
for i in "${!names[@]}"; do export "${names[$i]}=${values[$i]}"; done
[ -n "${DIGITALOCEAN_TOKEN:-}" ] || die "masings-tf-masing-demo-infra-env must set DIGITALOCEAN_TOKEN"

apps="$(fetch masings-tf-masing-demo-infra-apps-env)"
# Terraform reads a map variable from the environment as HCL, so escape template markers (${ and %{)
# to keep every app's .env byte for byte
TF_VAR_app_env_files="$(jq -ec 'if type == "object" and (map_values(type == "string") | all)
    then map_values(gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{"))
    else error("must be a JSON map of file name to content") end' < <(printf '%s' "$apps"))" \
    || die "Secret masings-tf-masing-demo-infra-apps-env is not a JSON map of file name to content"
export TF_VAR_app_env_files

# Only the state key may reach the state: drop anything that would override it or redirect the backend
unset GOOGLE_CREDENTIALS GOOGLE_OAUTH_ACCESS_TOKEN GOOGLE_APPLICATION_CREDENTIALS \
    GOOGLE_BACKEND_IMPERSONATE_SERVICE_ACCOUNT GOOGLE_IMPERSONATE_SERVICE_ACCOUNT \
    GOOGLE_BACKEND_STORAGE_CUSTOM_ENDPOINT GOOGLE_STORAGE_CUSTOM_ENDPOINT GOOGLE_ENCRYPTION_KEY
export GOOGLE_BACKEND_CREDENTIALS="$keys/masings-tf-state.json"

# Init on every run: a no-op when the backend matches, a hard stop when it changed (a local state
# file is refused above). Never pass -reconfigure or -migrate-state here: moving state is a reviewed step.
terraform -chdir="$dir" init -input=false >/dev/null

if [ "$cmd" = plan ] || [ "$cmd" = apply ]; then
    # A new droplet can only be reached by joining the tailnet on first boot
    resources=$(terraform -chdir="$dir" state list) || die "Cannot read the state (error above)"
    if ! grep -qx digitalocean_droplet.main <<<"$resources" && [ -z "${TF_VAR_tailscale_auth_key:-}" ]; then
        die "The droplet will be created: add TF_VAR_tailscale_auth_key to masings-tf-masing-demo-infra-env first (single-use, tagged key)"
    fi
fi
case "$cmd" in
    # A missing setting stops with an error instead of a prompt (apply still asks for approval)
    plan | apply | destroy | refresh | import) exec terraform -chdir="$dir" "$cmd" -input=false "$@" ;;
    *) exec terraform -chdir="$dir" "$cmd" "$@" ;;
esac
