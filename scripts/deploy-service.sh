#!/usr/bin/env bash
# Troca a imagem de um serviço de app por uma tag nova, espera ficar healthy e, se falhar,
# volta sozinho para a tag anterior e para o .env.production do último deploy que deu certo.
# Quem chama é o workflow de deploy (etapa "deploy"). Um deploy por serviço de cada vez (trava em arquivo).
# Uso: scripts/deploy-service.sh <produto> <serviço> <tag>   ex.: scripts/deploy-service.sh offer web <sha>
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 3 ]; then echo "uso: $0 <produto> <serviço> <tag>"; exit 2; fi
product=$1; service=$2; tag=$3
# Os três valores viram caminho e tag de imagem: só o formato esperado passa.
[[ "$product" =~ ^[a-z0-9][a-z0-9-]*$ && "$service" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "produto ou serviço inválido"; exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo "tag inválida"; exit 2; }
dir="apps/$product/production/$service"

[ -f "$dir/compose.yaml" ] || { echo "sem $dir/compose.yaml"; exit 1; }
[ -f "$dir/.env.production" ] || { echo "falta $dir/.env.production (o workflow grava antes de chamar este script)"; exit 1; }
chmod 600 "$dir/.env.production"

# Dois deploys do mesmo serviço ao mesmo tempo trocariam a tag um do outro: o segundo espera até 5 minutos.
exec 9>"$dir/.deploy.lock"
flock -w 300 9 || { echo "outro deploy de $product/$service ainda está em andamento"; exit 1; }

log="$dir/deploy.log"
# O log guarda só as últimas 500 linhas.
if [ -f "$log" ] && [ "$(wc -l < "$log")" -gt 500 ]; then tail -n 500 "$log" > "$log.tmp" && mv "$log.tmp" "$log"; fi
say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$log"; }

# Guarda só o IMAGE_TAG e preserva as demais linhas do .env (ex.: IMAGE_NAME).
current_tag() { sed -nE 's/^IMAGE_TAG=(.+)$/\1/p' "$dir/.env" 2>/dev/null | tail -1 || true; }
set_tag() {
  local tmp; tmp=$(mktemp "$dir/.env.XXXXXX")
  { grep -v '^IMAGE_TAG=' "$dir/.env" 2>/dev/null || true; printf 'IMAGE_TAG=%s\n' "$1"; } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$dir/.env"
}
apply() { (cd "$dir" && docker compose pull --quiet && docker compose up -d --wait --wait-timeout 180); }

# Cópia do .env.production do último deploy saudável (modo 600, fora do Git): é para ela que o rollback volta.
good="$dir/.env.production.ok"
save_env() { local tmp; tmp=$(mktemp "$dir/.env.XXXXXX"); cp "$dir/.env.production" "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$good"; }
restore_env() {
  [ -f "$good" ] || return 0
  cmp -s "$good" "$dir/.env.production" && return 0
  local tmp; tmp=$(mktemp "$dir/.env.XXXXXX"); cp "$good" "$tmp"; chmod 600 "$tmp"
  mv "$dir/.env.production" "$dir/.env.production.failed"; mv "$tmp" "$dir/.env.production"
  say "rollback do .env.production (o que falhou ficou em .env.production.failed)"
}

previous=$(current_tag)
scripts/bootstrap.sh >/dev/null

say "deploy $product/$service tag=$tag (anterior: ${previous:-nenhuma})"
set_tag "$tag"
if apply; then
  save_env
  say "ok $product/$service tag=$tag healthy"
  exit 0
fi

say "FALHOU $product/$service tag=$tag"
if [ -n "$previous" ] && [ "$previous" != "$tag" ]; then
  say "rollback para tag=$previous"
  set_tag "$previous"
  restore_env
  if apply; then say "rollback ok tag=$previous"; else say "rollback FALHOU tag=$previous"; fi
else
  say "sem tag anterior para voltar"
fi
exit 1
