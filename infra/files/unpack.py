import json, os, sys

# Writes every file from the deploy bundle; .env files are root-only.
# conf.d is synced: a site removed from Terraform is removed from Nginx too.
files = json.load(open(sys.argv[1]))
for path, content in files.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(content)
    os.chmod(tmp, 0o600 if path.endswith(".env") else (0o755 if path.endswith(".sh") else 0o644))
    os.replace(tmp, path)
confd = "/srv/proxy/conf.d"
for name in os.listdir(confd):
    if name.endswith(".conf") and os.path.join(confd, name) not in files:
        os.remove(os.path.join(confd, name))
        print("removed", name)
os.makedirs("/srv/proxy/certbot/www", exist_ok=True)
