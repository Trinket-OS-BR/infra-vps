#!/usr/bin/env bash
# Dump lógico de todos os bancos de aplicação, comprimido, com retenção.
# Uso: scripts/postgres-backup.sh [pasta=/srv/backups/postgres] [dias=7]
# Agendar (crontab do usuário deploy): 0 3 * * * /srv/infra-vps/scripts/postgres-backup.sh
set -euo pipefail

dir=${1:-/srv/backups/postgres}
days=${2:-7}
admin=$(docker exec platform-postgres printenv POSTGRES_USER)
stamp=$(date +%Y%m%d-%H%M%S)

umask 077
mkdir -p "$dir"
dbs=$(docker exec platform-postgres psql -p 4130 -U "$admin" -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'")

for db in $dbs; do
  file="$dir/$db-$stamp.sql.gz"
  docker exec platform-postgres pg_dump -p 4130 -U "$admin" -d "$db" --no-owner | gzip > "$file"
  echo "ok $file ($(du -h "$file" | cut -f1))"
done
find "$dir" -name '*.sql.gz' -mtime +"$days" -delete
