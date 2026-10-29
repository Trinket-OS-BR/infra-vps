#!/usr/bin/env bash
# Prepara um alvo: pede a senha de criptografia (sem eco), grava em /etc/infra-backup (600) e cria o
# repositório Restic no R2. Seguro para repetir: não sobrescreve senha nem reinicializa repositório.
# Uso: scripts/backup-init.sh <nome>      (antes: /etc/infra-backup/r2.env preenchido)
set -euo pipefail
. "$(dirname "$0")/backup-lib.sh"

name=${1:?uso: backup-init.sh <nome>}
load_target "$name"
umask 077
install -d -m 700 "$conf_dir"
pw="$conf_dir/$name.password"

if [ -e "$pw" ]; then
  echo "senha já existe em $pw; preservada."
else
  read -r -s -p "Senha de criptografia de '$name': " a; printf '\n'
  read -r -s -p "Confirme: " b; printf '\n'
  [ -n "$a" ] && [ "$a" = "$b" ] || { echo "senha vazia ou diferente"; exit 1; }
  printf '%s\n' "$a" > "$pw"; chmod 600 "$pw"
  echo "senha salva. Guarde também no gerenciador de senhas: sem ela os backups não abrem."
fi

restic_env "$name"
if "$restic_bin" cat config >/dev/null 2>&1; then
  echo "repositório já existe; nada a fazer."
else
  "$restic_bin" init
fi
echo "falta, se ainda não fez: $conf_dir/$name.heartbeat.env (modelo em platform/backup/)"
