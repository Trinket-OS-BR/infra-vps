#!/usr/bin/env bash
# Lista os snapshots de um alvo no R2 e a próxima execução do timer. Só leitura.
# Uso: scripts/backup-status.sh <nome>
set -euo pipefail
. "$(dirname "$0")/backup-lib.sh"

name=${1:?uso: backup-status.sh <nome>}
load_target "$name"
restic_env "$name"
echo "repositório: ${RESTIC_REPOSITORY%%/*}//.../${RESTIC_REPOSITORY##*/}"
"$restic_bin" snapshots --tag "$name,postgres" --compact
systemctl list-timers --all "infra-backup-$name.timer" --no-pager 2>/dev/null || true
