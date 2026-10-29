#!/usr/bin/env bash
# Gera (ou instala) um serviço e um timer do systemd por alvo de backups.list, cada um com a sua agenda.
# Uso: scripts/backup-systemd.sh            mostra as unidades, sem alterar nada
#      sudo scripts/backup-systemd.sh --apply   grava em /etc/systemd/system e habilita os timers
set -euo pipefail
. "$(dirname "$0")/backup-lib.sh"

apply=${1:-}
unit_dir=/etc/systemd/system
mapfile -t names < <(grep -vE '^\s*(#|$)' "$backup_root/backups.list" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')

for name in "${names[@]}"; do
  load_target "$name"
  service="[Unit]
Description=Backup PostgreSQL de $name para o R2
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
UMask=0077
ExecStart=$backup_root/scripts/backup-run.sh $name
"
  timer="[Unit]
Description=Agenda do backup de $name

[Timer]
OnCalendar=$schedule
Persistent=true
RandomizedDelaySec=5m
Unit=infra-backup-$name.service

[Install]
WantedBy=timers.target
"
  if [ "$apply" = "--apply" ]; then
    printf '%s' "$service" > "$unit_dir/infra-backup-$name.service"
    printf '%s' "$timer" > "$unit_dir/infra-backup-$name.timer"
    systemd-analyze calendar "$schedule" >/dev/null
  else
    printf '# infra-backup-%s.service\n%s\n# infra-backup-%s.timer\n%s\n' "$name" "$service" "$name" "$timer"
  fi
done

if [ "$apply" = "--apply" ]; then
  systemctl daemon-reload
  for name in "${names[@]}"; do systemctl enable --now "infra-backup-$name.timer"; done
  systemctl list-timers --all 'infra-backup-*' --no-pager
fi
