terraform {
  # Credentials: scripts/tf.sh sets GOOGLE_BACKEND_CREDENTIALS
  backend "gcs" {
    bucket = "masings-tfstate"
    prefix = "zuitt-demo-infra/infra"
  }

  required_version = ">= 1.6"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Token from DIGITALOCEAN_TOKEN (scripts/tf.sh loads it from .env)
provider "digitalocean" {}
