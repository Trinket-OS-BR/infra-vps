#!/usr/bin/env bash
# Funções comuns dos scripts backup-*. Use com: . "$(dirname "$0")/backup-lib.sh"
# Modelo (o mesmo do backup em produção do Trinketos): pg_dump -Fc dentro do contêiner, verificado,
# enviado com Restic (criptografado e deduplicado) ao R2, retenção por `restic forget --prune`,
# confirmação por heartbeat externo, agenda por timer do systemd.
set -euo pipefail

backup_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
conf_dir=${BACKUP_CONF_DIR:-/etc/infra-backup}
local_root=${BACKUP_DIR:-/var/backups/infra}
restic_bin=${RESTIC_BIN:-/usr/local/bin/restic}

_trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$1"; }

# Lê a linha do alvo em backups.list e define: container port admin db schedule within weekly monthly
load_target() {
  local name=$1 line retention
  line=$(grep -vE '^\s*(#|$)' "$backup_root/backups.list" |
    awk -v n="$name" 'BEGIN{FS=OFS="|"} {gsub(/^[ \t]+|[ \t]+$/,"",$1)} $1==n' | head -1)
  [ -n "$line" ] || { echo "alvo '$name' não está em backups.list (ou está comentado)" >&2; return 1; }
  IFS='|' read -r _ container port admin db schedule retention <<<"$line"
  container=$(_trim "$container"); port=$(_trim "$port"); admin=$(_trim "$admin"); db=$(_trim "$db")
  schedule=$(_trim "$schedule"); retention=$(_trim "$retention")
  [ "$admin" != "-" ] || admin=""
  within=${retention%%/*}; local rest=${retention#*/}; weekly=${rest%%/*}; monthly=${rest#*/}
  : "${within:?}" "${weekly:?}" "${monthly:?}"
}

# Variáveis do R2 e do repositório Restic deste alvo. Segredos só em /etc/infra-backup (600).
restic_env() {
  local name=$1
  [ -f "$conf_dir/r2.env" ] || { echo "falta $conf_dir/r2.env (modelo: platform/backup/r2.env.example)" >&2; return 1; }
  set -a; . "$conf_dir/r2.env"; set +a
  : "${R2_ENDPOINT:?}" "${R2_BUCKET:?}" "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}"
  # Opcional, para adotar um repositório Restic que já existe: /etc/infra-backup/<nome>.env com REPO_PATH=<caminho no bucket>.
  unset REPO_PATH
  if [ -f "$conf_dir/$name.env" ]; then set -a; . "$conf_dir/$name.env"; set +a; fi
  export RESTIC_PASSWORD_FILE="$conf_dir/$name.password"
  export RESTIC_REPOSITORY="s3:${R2_ENDPOINT%/}/$R2_BUCKET/${REPO_PATH:-$name}"
  [ -f "$RESTIC_PASSWORD_FILE" ] || { echo "falta $RESTIC_PASSWORD_FILE (rode scripts/backup-init.sh $name)" >&2; return 1; }
  [ -x "$restic_bin" ] || { echo "restic não encontrado em $restic_bin (ver Wiki, página de backup)" >&2; return 1; }
}

# pg_dump / psql dentro do contêiner; o usuário padrão vem do POSTGRES_USER do próprio contêiner.
pg_in_container() { # <comando-pg> <args...> ; stdin repassado
  local cmd=$1; shift
  docker exec -i -e PGADMIN="$admin" -e PGP="$port" "$container" \
    sh -c 'U=${PGADMIN:-${POSTGRES_USER:-postgres}}; c=$1; shift; exec "$c" -p "$PGP" -U "$U" "$@"' sh "$cmd" "$@"
}
