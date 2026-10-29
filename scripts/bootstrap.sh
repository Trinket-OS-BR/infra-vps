#!/usr/bin/env bash
# Cria as redes Docker da plataforma. Idempotente.
#   data: interna (sem internet, sem portas no host); bancos e quem os consome.
#   proxy: tráfego HTTP vindo do Caddy (criada quando o proxy entrar).
set -euo pipefail

docker network inspect data >/dev/null 2>&1 || docker network create --internal data
echo "redes prontas:"
docker network ls --filter name=^data$ --format '  {{.Name}} (internal={{.Internal}})'
