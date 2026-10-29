#!/usr/bin/env bash
# Faz o backup de UM alvo de backups.list: dump -Fc, verificação, envio ao R2 e retenção.
# Uso: scripts/backup-run.sh <nome>      (a agenda é do cron; ver scripts/backup-cron.sh)
# Credenciais do R2: /srv/secrets/r2.env (600), com R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID,
# R2_SECRET_ACCESS_KEY e, opcional, R2_PREFIX (padrão "backups"). Nada disso aparece em logs.
set -euo pipefail

name=${1:?uso: backup-run.sh <nome>}
root=$(cd "$(dirname "$0")/.." && pwd)
secrets=${R2_ENV_FILE:-/srv/secrets/r2.env}
localroot=${BACKUP_DIR:-/srv/backups}
RCLONE_IMAGE=rclone/rclone:1.68.2

line=$(grep -vE '^\s*(#|$)' "$root/backups.list" | awk -F'|' -v n="$name" '{gsub(/^ +| +$/,"",$1)} $1==n' | head -1)
[ -n "$line" ] || { echo "alvo '$name' não está em backups.list (ou está comentado)"; exit 1; }
IFS='|' read -r _ container port admin db _ days <<<"$line"
container=$(echo "$container" | xargs); port=$(echo "$port" | xargs); admin=$(echo "$admin" | xargs)
db=$(echo "$db" | xargs); days=$(echo "$days" | xargs)

[ -f "$secrets" ] || { echo "falta $secrets (modelo: platform/backup/r2.env.example)"; exit 1; }
set -a; . "$secrets"; set +a
: "${R2_ENDPOINT:?}" "${R2_BUCKET:?}" "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}"
prefix=${R2_PREFIX:-backups}

export RCLONE_S3_PROVIDER=Cloudflare RCLONE_S3_REGION=auto RCLONE_S3_NO_CHECK_BUCKET=true
export RCLONE_S3_ENDPOINT=$R2_ENDPOINT RCLONE_S3_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_S3_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
rclone() {
  docker run --rm -i -e RCLONE_S3_PROVIDER -e RCLONE_S3_REGION -e RCLONE_S3_NO_CHECK_BUCKET \
    -e RCLONE_S3_ENDPOINT -e RCLONE_S3_ACCESS_KEY_ID -e RCLONE_S3_SECRET_ACCESS_KEY \
    -v "$localroot/$name:/data" "$RCLONE_IMAGE" "$@"
}

umask 077
mkdir -p "$localroot/$name"
exec 9>"$localroot/$name/.lock"
flock -n 9 || { echo "backup de '$name' já em andamento"; exit 1; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
file="$db-$stamp.dump"
echo "[$(date -u +%FT%TZ)] $name: dump de $db em $container"
docker exec "$container" pg_dump -p "$port" -U "$admin" -d "$db" -Fc --no-owner > "$localroot/$name/$file"

# Um dump truncado não serve: confere que o arquivo é legível e não está vazio.
docker exec -i "$container" pg_restore --list < "$localroot/$name/$file" >/dev/null
size=$(du -h "$localroot/$name/$file" | cut -f1)

remote=":s3:$R2_BUCKET/$prefix/$name"
rclone copyto "/data/$file" "$remote/$file"
rclone delete --min-age "${days}d" "$remote"
find "$localroot/$name" -maxdepth 1 -name '*.dump' -mtime +1 -delete
echo "[$(date -u +%FT%TZ)] $name: ok $file ($size), retenção ${days}d no R2"
