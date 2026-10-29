#!/usr/bin/env bash
# Sobe tudo que está em services.list, na ordem, e espera cada serviço ficar healthy.
# Idempotente: rodar de novo só aplica o que mudou. Uso: scripts/up.sh [pasta-do-serviço]
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bootstrap.sh

if [ $# -gt 0 ]; then services=("$@"); else
  mapfile -t services < <(grep -vE '^\s*(#|$)' services.list)
fi

for svc in "${services[@]}"; do
  [ -f "$svc/compose.yaml" ] || { echo "sem $svc/compose.yaml"; exit 1; }
  for e in .env .env.production; do
    if grep -q "$e" "$svc/compose.yaml" && [ ! -f "$svc/$e" ]; then
      echo "falta $svc/$e (copie de $e.example e preencha)"; exit 1
    fi
    [ ! -f "$svc/$e" ] || chmod 600 "$svc/$e"
  done
  echo "==> $svc"
  (cd "$svc" && docker compose pull --quiet && docker compose up -d --wait --wait-timeout 180)
done
echo "tudo healthy:"; docker ps --format '  {{.Names}}\t{{.Status}}'
