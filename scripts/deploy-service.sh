#!/usr/bin/env bash
# Troca a imagem de um serviço de app por uma tag nova, espera ficar healthy e, se falhar,
# volta sozinho para a tag anterior. Quem chama é o workflow de deploy (etapa "deploy").
# Uso: scripts/deploy-service.sh <produto> <serviço> <tag>   ex.: scripts/deploy-service.sh offer web <sha>
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 3 ]; then echo "uso: $0 <produto> <serviço> <tag>"; exit 2; fi
product=$1; service=$2; tag=$3
dir="apps/$product/production/$service"

[ -f "$dir/compose.yaml" ] || { echo "sem $dir/compose.yaml"; exit 1; }
[ -f "$dir/.env.production" ] || { echo "falta $dir/.env.production (o workflow grava antes de chamar este script)"; exit 1; }
chmod 600 "$dir/.env.production"

log="$dir/deploy.log"
say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$log"; }

# Guarda só o IMAGE_TAG e preserva as demais linhas do .env (ex.: IMAGE_NAME).
current_tag() { sed -nE 's/^IMAGE_TAG=(.+)$/\1/p' "$dir/.env" 2>/dev/null | tail -1 || true; }
set_tag() {
  local tmp; tmp=$(mktemp "$dir/.env.XXXXXX")
  { grep -v '^IMAGE_TAG=' "$dir/.env" 2>/dev/null || true; printf 'IMAGE_TAG=%s\n' "$1"; } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$dir/.env"
}
apply() { (cd "$dir" && docker compose pull --quiet && docker compose up -d --wait --wait-timeout 180); }

previous=$(current_tag)
scripts/bootstrap.sh >/dev/null

say "deploy $product/$service tag=$tag (anterior: ${previous:-nenhuma})"
set_tag "$tag"
if apply; then
  say "ok $product/$service tag=$tag healthy"
  exit 0
fi

say "FALHOU $product/$service tag=$tag"
if [ -n "$previous" ] && [ "$previous" != "$tag" ]; then
  say "rollback para tag=$previous"
  set_tag "$previous"
  if apply; then say "rollback ok tag=$previous"; else say "rollback FALHOU tag=$previous"; fi
else
  say "sem tag anterior para voltar"
fi
exit 1
