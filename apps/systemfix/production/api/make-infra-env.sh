#!/usr/bin/env bash
# Monta, na VPS e com modo 600, os arquivos de credenciais da API do System Fix a partir do que os scripts
# da plataforma já gravaram em /srv/secrets. Nada é impresso. Rode depois de criar banco e usuário Redis
# do produto; rode de novo se uma senha mudar.
#   scripts/postgres-create-db.sh systemfix /srv/secrets/systemfix-db.env
#   scripts/redis-create-user.sh systemfix /srv/secrets/systemfix-redis.env
#   apps/systemfix/production/api/make-infra-env.sh
# Gera:
#   systemfix-api-infra.env  usado pela API em execução (papel restrito system_fix_runtime e Redis com prefixo)
#   systemfix-migrate.env    usado só pela tarefa de migração (conexão administrativa); apague depois com --cleanup
set -euo pipefail
umask 077
S=/srv/secrets
if [ "${1:-}" = "--cleanup" ]; then rm -f "$S/systemfix-migrate.env"; echo "removido $S/systemfix-migrate.env"; exit 0; fi
for f in systemfix-db systemfix-redis; do
  [ -f "$S/$f.env" ] || { echo "falta $S/$f.env (rode o script de criação correspondente)"; exit 1; }
done
get() { grep "^$2=" "$1" | head -1 | cut -d= -f2-; }

# DATABASE_URL = postgresql://usuario:senha@host:porta/banco
URL=$(get $S/systemfix-db.env DATABASE_URL); REST=${URL#*://}; HP=${REST#*@}; DBN=${HP#*/}; DBN=${DBN%%\?*}; HOSTPORT=${HP%%/*}
# A senha do papel restrito é gerada uma vez e reaproveitada nas execuções seguintes.
APP_PASS_FILE=$S/systemfix-runtime.pass
[ -f "$APP_PASS_FILE" ] || { openssl rand -hex 24 > "$APP_PASS_FILE"; chmod 600 "$APP_PASS_FILE"; }
APP_PASS=$(cat "$APP_PASS_FILE")

{
  echo "DATABASE_URL=postgresql://system_fix_runtime:$APP_PASS@$HOSTPORT/$DBN"
  echo "REDIS_URL=$(get $S/systemfix-redis.env REDIS_URL)"
  echo "REDIS_KEY_PREFIX=$(get $S/systemfix-redis.env REDIS_KEY_PREFIX)"
} > "$S/systemfix-api-infra.env.tmp"
chmod 600 "$S/systemfix-api-infra.env.tmp"; mv "$S/systemfix-api-infra.env.tmp" "$S/systemfix-api-infra.env"

# A migração cria o papel system_fix_runtime (nível do cluster), então precisa do administrador do Postgres,
# lido do próprio contêiner como nos demais scripts da plataforma.
ADMIN=$(docker exec platform-postgres printenv POSTGRES_USER)
ADMIN_PASS=$(docker exec platform-postgres printenv POSTGRES_PASSWORD)
{
  echo "MIGRATION_DATABASE_URL=postgresql://$ADMIN:$ADMIN_PASS@$HOSTPORT/$DBN"
  echo "DATABASE_APP_PASSWORD=$APP_PASS"
} > "$S/systemfix-migrate.env.tmp"
chmod 600 "$S/systemfix-migrate.env.tmp"; mv "$S/systemfix-migrate.env.tmp" "$S/systemfix-migrate.env"
echo "gravado $S/systemfix-api-infra.env e $S/systemfix-migrate.env (apague o segundo depois: $0 --cleanup)"
