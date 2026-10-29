#!/usr/bin/env bash
# Backup de UM alvo de backups.list: dump -Fc, verificação, Restic para o R2, retenção, check e heartbeat.
# Uso: scripts/backup-run.sh <nome>      (a agenda é do systemd; ver scripts/backup-systemd.sh)
set -euo pipefail
. "$(dirname "$0")/backup-lib.sh"

name=${1:?uso: backup-run.sh <nome>}
load_target "$name"
restic_env "$name"

umask 077
mkdir -p "$local_root/$name"
exec 9>"$local_root/$name/.lock"
flock -n 9 || { echo "backup de '$name' já em andamento"; exit 1; }

file="$local_root/$name/$db-full.dump"
echo "[$(date -u +%FT%TZ)] $name: dump de $db em $container"
pg_in_container pg_dump -d "$db" -Fc > "$file.partial"

# Dump truncado não serve: o índice precisa ser legível antes de publicar o arquivo final.
pg_in_container pg_restore --list < "$file.partial" >/dev/null
mv "$file.partial" "$file"

"$restic_bin" backup "$file" --tag "$name" --tag postgres
# Retenção segura pelo próprio Restic. Nunca aplique expiração do R2 sobre este repositório.
TZ=America/Sao_Paulo "$restic_bin" forget --tag "$name,postgres" --group-by host \
  --keep-within "$within" --keep-weekly "$weekly" --keep-monthly "$monthly" --prune
"$restic_bin" check

# Aviso externo: sem este sinal, a ausência do backup é detectada pelo monitor (intervalo + tolerância).
hb="$conf_dir/$name.heartbeat.env"
[ -f "$hb" ] || { echo "backup salvo, mas falta $hb (heartbeat é obrigatório)"; exit 1; }
set -a; . "$hb"; set +a
curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --retry 2 "${BETTERSTACK_HEARTBEAT_URL:?}" >/dev/null

echo "[$(date -u +%FT%TZ)] $name: backup concluído"
