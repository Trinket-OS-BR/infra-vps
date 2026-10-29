#!/usr/bin/env bash
# Cria o usuário Redis de um produto (ACL): só enxerga chaves e canais com o prefixo "<nome>:" e não roda
# comandos perigosos nem administrativos. A senha é gerada aqui, gravada no arquivo indicado (modo 600)
# e nunca impressa. Uso: scripts/redis-create-user.sh <nome> <arquivo-de-saida>
#   ex.: scripts/redis-create-user.sh meuapp /srv/secrets/meuapp-redis.env
# O app deve prefixar TODAS as chaves com "<nome>:" (a ACL recusa o resto) e usar TTL no que for cache.
set -euo pipefail

name=${1:?uso: redis-create-user.sh <nome> <arquivo-de-saida>}
out=${2:?informe o arquivo de saída}
[[ "$name" =~ ^[a-z][a-z0-9_]{1,30}$ ]] || { echo "nome inválido (minúsculas, números, _)"; exit 1; }
case "$name" in default|admin) echo "nome reservado"; exit 1 ;; esac
[ ! -e "$out" ] || { echo "$out já existe; não sobrescrevo"; exit 1; }

# redis-cli como administrador, dentro do contêiner (a senha do admin nunca sai de lá).
rcli() { docker exec -i platform-redis sh -c 'REDISCLI_AUTH="$REDIS_ADMIN_PASSWORD" exec redis-cli -p 4131 --user admin'; }

if printf 'ACL USERS\n' | rcli | grep -qx "$name"; then echo "usuário '$name' já existe no Redis"; exit 1; fi

pass=$(openssl rand -hex 24)
# -select e -scan: o usuário fica no banco 0 e não lista chaves de outros produtos.
reply=$(printf 'ACL SETUSER %s on >%s ~%s:* &%s:* +@all -@dangerous -@admin -select -scan\nACL SAVE\n' \
  "$name" "$pass" "$name" "$name" | rcli)
[ "$(printf '%s\n' "$reply" | grep -cx OK)" -eq 2 ] || { echo "falha ao criar o usuário (resposta inesperada do Redis)"; exit 1; }

umask 077
mkdir -p "$(dirname "$out")"
printf 'REDIS_URL=redis://%s:%s@platform-redis:4131\nREDIS_KEY_PREFIX=%s:\n' "$name" "$pass" "$name" > "$out"
echo "usuário '$name' criado (chaves '$name:*'); credenciais em $out (600)"
