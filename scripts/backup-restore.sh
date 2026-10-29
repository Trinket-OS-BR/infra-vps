#!/usr/bin/env bash
# Restaura um backup do R2 em um banco NOVO (nunca sobrescreve um existente).
# Uso: scripts/backup-restore.sh <nome> <latest|arquivo.dump> <banco-destino>
#   ex.: scripts/backup-restore.sh offer latest teste_restore
# Para substituir produção: restaure num banco novo, confira e só então troque os bancos.
set -euo pipefail

name=${1:?uso: backup-restore.sh <nome> <latest|arquivo> <banco-destino>}
which=${2:?informe latest ou o nome do arquivo}
target=${3:?informe o banco de destino (novo)}
root=$(cd "$(dirname "$0")/.." && pwd)
secrets=${R2_ENV_FILE:-/srv/secrets/r2.env}
localroot=${BACKUP_DIR:-/srv/backups}
RCLONE_IMAGE=rclone/rclone:1.68.2

line=$(grep -vE '^\s*(#|$)' "$root/backups.list" | awk -F'|' -v n="$name" '{gsub(/^ +| +$/,"",$1)} $1==n' | head -1)
[ -n "$line" ] || { echo "alvo '$name' não está em backups.list"; exit 1; }
IFS='|' read -r _ container port admin db _ _ <<<"$line"
container=$(echo "$container" | xargs); port=$(echo "$port" | xargs); admin=$(echo "$admin" | xargs); db=$(echo "$db" | xargs)
[ "$target" != "$db" ] || { echo "o destino não pode ser o banco de produção ($db)"; exit 1; }
[[ "$target" =~ ^[a-z][a-z0-9_]{1,40}$ ]] || { echo "nome de destino inválido"; exit 1; }

set -a; . "$secrets"; set +a
prefix=${R2_PREFIX:-backups}
export RCLONE_S3_PROVIDER=Cloudflare RCLONE_S3_REGION=auto RCLONE_S3_NO_CHECK_BUCKET=true
export RCLONE_S3_ENDPOINT=$R2_ENDPOINT RCLONE_S3_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_S3_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
rclone() {
  docker run --rm -i -e RCLONE_S3_PROVIDER -e RCLONE_S3_REGION -e RCLONE_S3_NO_CHECK_BUCKET \
    -e RCLONE_S3_ENDPOINT -e RCLONE_S3_ACCESS_KEY_ID -e RCLONE_S3_SECRET_ACCESS_KEY \
    -v "$localroot/$name:/data" "$RCLONE_IMAGE" "$@"
}

remote=":s3:$R2_BUCKET/$prefix/$name"
umask 077; mkdir -p "$localroot/$name"
if [ "$which" = latest ]; then
  which=$(rclone lsf --files-only "$remote" | sort | tail -1 | tr -d '\r')
  [ -n "$which" ] || { echo "nenhum backup encontrado em $remote"; exit 1; }
fi
echo "restaurando $which em $target"
rclone copyto "$remote/$which" "/data/$which"

docker exec "$container" createdb -p "$port" -U "$admin" "$target"
docker exec -i "$container" pg_restore -p "$port" -U "$admin" -d "$target" --no-owner < "$localroot/$name/$which"
echo "ok: banco '$target' restaurado. Confira com: docker exec $container psql -p $port -U $admin -d $target -c '\\dt'"
