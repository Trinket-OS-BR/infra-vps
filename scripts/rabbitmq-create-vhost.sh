#!/usr/bin/env bash
# Cria o vhost e o usuário de um produto no RabbitMQ compartilhado. O usuário só tem permissão no próprio
# vhost (nenhuma no padrão "/" nem nos vhosts de outros produtos) e nenhuma etiqueta de gestão.
# A senha é gerada aqui, gravada no arquivo indicado (modo 600) e nunca impressa.
# Uso: scripts/rabbitmq-create-vhost.sh <nome> <arquivo-de-saida>
#   ex.: scripts/rabbitmq-create-vhost.sh meuapp /srv/secrets/meuapp-rabbitmq.env
set -euo pipefail

name=${1:?uso: rabbitmq-create-vhost.sh <nome> <arquivo-de-saida>}
out=${2:?informe o arquivo de saída}
[[ "$name" =~ ^[a-z][a-z0-9_]{1,30}$ ]] || { echo "nome inválido (minúsculas, números, _)"; exit 1; }
case "$name" in guest|admin|platform_admin) echo "nome reservado"; exit 1 ;; esac
[ ! -e "$out" ] || { echo "$out já existe; não sobrescrevo"; exit 1; }

ctl() { docker exec platform-rabbitmq rabbitmqctl --quiet "$@"; }

if ctl list_vhosts --silent | grep -qx "$name"; then echo "vhost '$name' já existe"; exit 1; fi
if ctl list_users --silent | cut -f1 | grep -qx "$name"; then echo "usuário '$name' já existe"; exit 1; fi

pass=$(openssl rand -hex 24)
ctl add_vhost "$name" >/dev/null
# A senha entra por stdin: não aparece nos argumentos do docker exec nem no histórico.
printf '%s' "$pass" | docker exec -i platform-rabbitmq sh -c 'rabbitmqctl --quiet add_user "$1" "$(cat)"' _ "$name" >/dev/null
ctl set_permissions -p "$name" "$name" ".*" ".*" ".*" >/dev/null

umask 077
mkdir -p "$(dirname "$out")"
{
  printf 'RABBITMQ_HOST=platform-rabbitmq\nRABBITMQ_AMQP_PORT=4132\nRABBITMQ_STOMP_PORT=4133\n'
  printf 'RABBITMQ_VHOST=%s\nRABBITMQ_USER=%s\nRABBITMQ_PASSWORD=%s\n' "$name" "$name" "$pass"
  printf 'RABBITMQ_AMQP_URL=amqp://%s:%s@platform-rabbitmq:4132/%s\n' "$name" "$pass" "$name"
} > "$out"
echo "vhost e usuário '$name' criados; credenciais em $out (600)"
