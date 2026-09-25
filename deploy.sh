#!/usr/bin/env bash
# CI deploy: pull $1 and roll the tiket-app container on THIS web VM.
# Registry credentials come from /root/tiket-deploy.env (written by the
# Ansible playbook from the vault); container config comes from
# /root/tiket-app.env — the same env file the playbook's docker_container
# task uses, so provision and CI deploys configure the container identically.
set -euo pipefail
TAG=${1:?usage: deploy.sh TAG}
. /root/tiket-deploy.env
docker login -u "$REGISTRY_USER" -p "$REGISTRY_PASSWORD" "$REGISTRY" >/dev/null
docker pull "$REGISTRY/tiket-app:$TAG"
docker rm -f tiket-app
docker run -d --name tiket-app \
  --hostname "$(hostname -s)" \
  --restart unless-stopped \
  -p 127.0.0.1:8000:8000 \
  --env-file /root/tiket-app.env \
  "$REGISTRY/tiket-app:$TAG"
