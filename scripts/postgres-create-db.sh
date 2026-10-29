#!/usr/bin/env bash
# Cria banco e usuário próprios de uma aplicação (um por produto). A senha é gerada aqui,
# gravada no arquivo indicado (modo 600) e nunca impressa.
# Uso: scripts/postgres-create-db.sh <nome> <arquivo-de-saida>
#   ex.: scripts/postgres-create-db.sh offer /srv/secrets/offer-db.env
set -euo pipefail

name=${1:?uso: postgres-create-db.sh <nome> <arquivo-de-saida>}
out=${2:?informe o arquivo de saída}
[[ "$name" =~ ^[a-z][a-z0-9_]{1,30}$ ]] || { echo "nome inválido (minúsculas, números, _)"; exit 1; }
[ ! -e "$out" ] || { echo "$out já existe; não sobrescrevo"; exit 1; }

admin=$(docker exec platform-postgres printenv POSTGRES_USER)
pass=$(openssl rand -hex 24)

docker exec -i platform-postgres psql -p 4130 -U "$admin" -d postgres -v ON_ERROR_STOP=1 \
  -v name="$name" -v pass="$pass" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'name', :'pass') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'name', :'name') \gexec
SQL
docker exec platform-postgres psql -p 4130 -U "$admin" -d "$name" -c "REVOKE ALL ON DATABASE \"$name\" FROM PUBLIC;" >/dev/null

umask 077
mkdir -p "$(dirname "$out")"
printf 'DATABASE_URL=postgresql://%s:%s@platform-postgres:4130/%s\nDATABASE_SSL=false\n' "$name" "$pass" "$name" > "$out"
echo "banco '$name' criado; credenciais em $out (600)"
