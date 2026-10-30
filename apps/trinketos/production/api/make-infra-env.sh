#!/usr/bin/env bash
# Monta /srv/secrets/trinketos-api-infra.env (modo 600) a partir dos arquivos que os scripts da
# plataforma já gravaram em /srv/secrets. Nada é impresso. Rode depois de criar banco, usuário Redis,
# vhost do RabbitMQ e organização do OpenObserve do produto; rode de novo se uma senha mudar.
set -euo pipefail
umask 077
S=/srv/secrets
OUT=$S/trinketos-api-infra.env
for f in trinketos-db trinketos-redis trinketos-rabbitmq trinketos-observability; do
  [ -f "$S/$f.env" ] || { echo "falta $S/$f.env (rode o script de criação correspondente)"; exit 1; }
done
get() { grep "^$2=" "$1" | head -1 | cut -d= -f2-; }

# DATABASE_URL = postgres://usuario:senha@host:porta/banco?...
URL=$(get $S/trinketos-db.env DATABASE_URL); REST=${URL#*://}; CRED=${REST%%@*}; HP=${REST#*@}
DBN=${HP#*/}; DBN=${DBN%%\?*}
# REDIS_URL = redis://usuario:senha@host:porta
RURL=$(get $S/trinketos-redis.env REDIS_URL); RR=${RURL#*://}; RC=${RR%%@*}; RHP=${RR#*@}
RB=$S/trinketos-rabbitmq.env

{
  echo "DB_URL=jdbc:postgresql://${HP%%/*}/$DBN?currentSchema=production"
  echo "DB_USERNAME=${CRED%%:*}"
  echo "DB_PASSWORD=${CRED#*:}"
  echo "REDIS_HOST=${RHP%%:*}"
  echo "REDIS_PORT=${RHP#*:}"
  echo "REDIS_USERNAME=${RC%%:*}"
  echo "REDIS_PASSWORD=${RC#*:}"
  echo "REDIS_KEY_PREFIX=$(get $S/trinketos-redis.env REDIS_KEY_PREFIX)"
  echo "RABBITMQ_HOST=$(get $RB RABBITMQ_HOST)"
  echo "RABBITMQ_PORT=$(get $RB RABBITMQ_AMQP_PORT)"
  echo "RABBITMQ_VHOST=$(get $RB RABBITMQ_VHOST)"
  echo "RABBITMQ_USER=$(get $RB RABBITMQ_USER)"
  echo "RABBITMQ_PASSWORD=$(get $RB RABBITMQ_PASSWORD)"
  echo "RABBITMQ_STOMP_LOGIN=$(get $RB RABBITMQ_USER)"
  echo "RABBITMQ_STOMP_PASSCODE=$(get $RB RABBITMQ_PASSWORD)"
  echo "STOMP_RELAY_HOST=$(get $RB RABBITMQ_HOST)"
  echo "STOMP_RELAY_PORT=$(get $RB RABBITMQ_STOMP_PORT)"
  grep -E '^OTEL_EXPORTER_|^OBSERVABILITY_' $S/trinketos-observability.env
} > "$OUT.tmp"
chmod 600 "$OUT.tmp"; mv "$OUT.tmp" "$OUT"
echo "gravado $OUT ($(wc -l < "$OUT") variáveis)"
