#!/usr/bin/env bash
# Restaura um snapshot do R2 em um banco NOVO (nunca sobrescreve um existente nem a produção).
# Uso: scripts/backup-restore.sh <nome> <latest|id-do-snapshot> <banco-destino>
#   ex.: scripts/backup-restore.sh offer latest teste_restore
set -euo pipefail
. "$(dirname "$0")/backup-lib.sh"

name=${1:?uso: backup-restore.sh <nome> <latest|snapshot> <banco-destino>}
snap=${2:?informe latest ou o id do snapshot}
target=${3:?informe o banco de destino (novo)}
load_target "$name"
[ "$target" != "$db" ] || { echo "o destino não pode ser o banco de produção ($db)"; exit 1; }
[[ "$target" =~ ^[a-z][a-z0-9_]{1,40}$ ]] || { echo "nome de destino inválido"; exit 1; }
restic_env "$name"

umask 077
tmp=$(mktemp -d "$local_root/$name/restore.XXXXXX") || { mkdir -p "$local_root/$name"; tmp=$(mktemp -d "$local_root/$name/restore.XXXXXX"); }
trap 'rm -rf "$tmp"' EXIT
"$restic_bin" restore "$snap" --tag "$name,postgres" --target "$tmp"
dump=$(find "$tmp" -type f -name '*.dump' | head -1)
[ -n "$dump" ] || { echo "dump não encontrado no snapshot"; exit 1; }

pg_in_container createdb -T template0 "$target"
pg_in_container pg_restore --exit-on-error --single-transaction --no-owner --no-privileges -d "$target" < "$dump"
echo "ok: banco '$target' restaurado (owners e grants omitidos de propósito). Confira as tabelas e depois remova com dropdb."
