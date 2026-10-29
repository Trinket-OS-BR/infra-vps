#!/usr/bin/env bash
# Gera (ou instala) o bloco do crontab com a agenda de cada alvo de backups.list.
# Uso: scripts/backup-cron.sh            mostra o bloco, sem alterar nada
#      scripts/backup-cron.sh --apply    instala no crontab do usuário (só o bloco marcado)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
logroot=${BACKUP_DIR:-/srv/backups}
begin='# BEGIN infra-vps backups'; end='# END infra-vps backups'

block="$begin"$'\n'
while IFS='|' read -r name _ _ _ _ schedule _; do
  name=$(echo "$name" | xargs); schedule=$(echo "$schedule" | xargs)
  [ -n "$name" ] || continue
  block+="$schedule $root/scripts/backup-run.sh $name >> $logroot/$name/backup.log 2>&1"$'\n'
done < <(grep -vE '^\s*(#|$)' "$root/backups.list")
block+="$end"

if [ "${1:-}" != "--apply" ]; then echo "$block"; exit 0; fi

current=$(crontab -l 2>/dev/null || true)
kept=$(printf '%s\n' "$current" | awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}')
while IFS='|' read -r name _; do
  name=$(echo "$name" | xargs); [ -n "$name" ] && mkdir -p "$logroot/$name"
done < <(grep -vE '^\s*(#|$)' "$root/backups.list")
printf '%s\n%s\n' "$kept" "$block" | sed '/^$/N;/^\n$/D' | crontab -
echo "crontab atualizado:"; crontab -l | sed -n "/$begin/,/$end/p"
