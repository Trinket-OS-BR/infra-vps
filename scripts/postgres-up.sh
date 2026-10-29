#!/usr/bin/env bash
# Sobe o Postgres da plataforma e espera ficar healthy.
set -euo pipefail
cd "$(dirname "$0")/../platform/postgres"

[ -f .env ] || { echo "falta platform/postgres/.env (copie de .env.example e gere a senha)"; exit 1; }
grep -q 'CHANGE_ME' .env && { echo "troque CHANGE_ME em .env"; exit 1; }
[ "$(stat -c %a .env)" = 600 ] || chmod 600 .env
docker network inspect data >/dev/null 2>&1 || { echo "rode scripts/bootstrap.sh antes"; exit 1; }

docker compose config --quiet
docker compose pull
docker compose up -d

status=starting
for _ in $(seq 1 30); do
  status=$(docker inspect -f '{{.State.Health.Status}}' platform-postgres)
  [ "$status" = healthy ] && break
  sleep 5
done
if [ "$status" != healthy ]; then
  docker logs --tail 50 platform-postgres
  echo "platform-postgres NÃO ficou healthy"; exit 1
fi
echo "platform-postgres healthy"
