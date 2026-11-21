droplet_name = "masing-demo"
region       = "sgp1"
droplet_size = "s-1vcpu-2gb"

do_ssh_keys = ["9c:15:66:1f:ee:45:ce:75:fd:fe:1e:87:f4:fd:55:b7"] # Kenneth@MacbookPro

kenneth_ssh_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOoXCFrKtvMYYNKkwKQfZbCC3kcpYitUo0zgT0IJ/v7B kennmasing@KENNETHs-MacBook-Pro.local",
]

hermes_ssh_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIONx3BiyodRoZM6HKbjVL1P+VCD6TOF3swgD38tQaAMr hermes@kennmasing-mac zuitt-demo",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAjywVC8RqTMzyHgfbRt3BYQCFR9UA+KJ3vytpuw5Z3F masings@agentic-loop hermes-cloud", # deploy key: Terraform on agentic-loop
]

deploy_host = "masing-demo"

# GHCR tags built by each app repo's "Publish image" workflow (sha-<7-char commit>)
image_tags = {
  "portfolio"                = "sha-ca771b6"
  "kisetsuspa-web"           = "sha-1b80f74"
  "airline-booking-system"   = "sha-6045e42"
  "masings-calculator"       = "sha-85eb9ed"
  "auth-app-server"          = "sha-fde72b7"
  "auth-app-client"          = "sha-fde72b7"
  "kisetsu-scheduler-server" = "sha-ff33685"
  "kisetsu-scheduler-client" = "sha-0ee9584"
  "b40-capstone1-revamp"     = "sha-PENDING" # set after b40-capstone1-revamp PR #1 publishes the image
}

# One conf.d/<key>.conf each, from files/site.conf.tftpl. Sites needing custom routing:
# put a hand-written file in proxy/conf.d/ instead.
simple_sites = {
  portfolio = {
    host     = "portfolio.masings.com"
    upstream = "portfolio:80"
  }
  kisetsuspa = {
    host     = "kisetsuspa.masings.com"
    upstream = "kisetsuspa:80"
  }
  airline-booking-system = {
    host     = "airline-booking-system.masings.com"
    upstream = "airline-booking-system:80"
  }
  altmobility = {
    host     = "altmobility.masings.com"
    upstream = "altmobility:80"
  }
}

cert_name     = "masings-apps"
certbot_email = "kennethmasing@gmail.com"
