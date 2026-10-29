#!/usr/bin/env bash
# Cria a organização e o usuário de envio de um produto no OpenObserve compartilhado. O usuário só existe na própria
# organização (não lê nem escreve nas outras). A senha é gerada aqui, gravada no arquivo indicado (modo 600) e nunca impressa.
# Uso: scripts/observability-create-org.sh <nome> <arquivo-de-saida>
#   ex.: scripts/observability-create-org.sh meuapp /srv/secrets/meuapp-observability.env
set -euo pipefail

name=${1:?uso: observability-create-org.sh <nome> <arquivo-de-saida>}
out=${2:?informe o arquivo de saída}
c=${O2_CONTAINER:-platform-openobserve}
[[ "$name" =~ ^[a-z][a-z0-9_]{1,30}$ ]] || { echo "nome inválido (minúsculas, números, _)"; exit 1; }
case "$name" in default|_meta|root|admin|platform) echo "nome reservado"; exit 1 ;; esac
[ ! -e "$out" ] || { echo "$out já existe; não sobrescrevo"; exit 1; }

# api <método> <caminho> [corpo-json]: usa o administrador raiz de dentro do contêiner (a senha não passa por argumentos).
api() {
  local method=$1 path=$2 body=${3:-}
  printf '%s' "$body" | docker exec -i "$c" sh -c \
    'curl -sS -X "$0" -u "$ZO_ROOT_USER_EMAIL:$ZO_ROOT_USER_PASSWORD" -H "Content-Type: application/json" --data-binary @- "http://localhost:4140$1"' "$method" "$path"
}

api GET /api/organizations | grep -q "\"name\":\"$name\"" && { echo "organização '$name' já existe"; exit 1; }

org_json=$(api POST /api/organizations "{\"name\":\"$name\"}")
id=$(sed -n 's/.*"identifier":"\([^"]*\)".*/\1/p' <<<"$org_json")
[ -n "$id" ] || { echo "não consegui criar a organização"; exit 1; }

pass="Aa1!$(openssl rand -hex 16)"
email="$name@ingest.invalid"
res=$(api POST "/api/$id/users" "{\"email\":\"$email\",\"password\":\"$pass\",\"first_name\":\"$name\",\"last_name\":\"ingest\",\"role\":\"admin\"}")
grep -q '"code":200' <<<"$res" || { echo "não consegui criar o usuário: $res"; exit 1; }

umask 077
mkdir -p "$(dirname "$out")"
auth=$(printf '%s:%s' "$email" "$pass" | base64 | tr -d '\n')
{
  printf 'OTEL_EXPORTER_OTLP_ENDPOINT=http://%s:4140/api/%s\n' "$c" "$id"
  printf 'OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf\n'
  printf 'OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic%%20%s\n' "$auth"
  printf 'OBSERVABILITY_ORG=%s\nOBSERVABILITY_USER=%s\nOBSERVABILITY_PASSWORD=%s\n' "$id" "$email" "$pass"
} > "$out"
echo "organização e usuário '$name' criados; credenciais em $out (600)"
