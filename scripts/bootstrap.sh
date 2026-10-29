#!/usr/bin/env bash
# Cria as redes Docker da plataforma. Idempotente.
#   data: interna (sem internet, sem portas no host); bancos e quem os consome.
#   proxy: tráfego HTTP vindo do Caddy e saída para a internet das apps (R2).
set -euo pipefail

docker network inspect data >/dev/null 2>&1 || docker network create --internal data
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
echo "redes prontas:"
docker network ls --filter name=^data$ --filter name=^proxy$ --format '  {{.Name}} (internal={{.Internal}})'
