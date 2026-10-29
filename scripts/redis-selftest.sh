#!/usr/bin/env bash
# Prova que dois produtos não se enxergam no Redis compartilhado: cria dois usuários temporários, tenta
# cruzar as fronteiras e apaga tudo no fim. Sai com código diferente de 0 se algum isolamento falhar.
# Uso: scripts/redis-selftest.sh   (com platform-redis no ar)
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); fail=0
admin() { docker exec -i platform-redis sh -c 'REDISCLI_AUTH="$REDIS_ADMIN_PASSWORD" exec redis-cli -p 4131 --user admin' "$@"; }
cleanup() {
  printf 'DEL selftest_a:k\nACL DELUSER selftest_a selftest_b\nACL SAVE\n' | admin >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT

for u in selftest_a selftest_b; do
  scripts/redis-create-user.sh "$u" "$tmp/$u.env" >/dev/null || { echo "não consegui criar $u"; exit 1; }
done
pw() { sed -n 's#^REDIS_URL=redis://[^:]*:\([^@]*\)@.*#\1#p' "$tmp/$1.env"; }

# as <usuário> <comando...>: roda como o produto e devolve a resposta (stdout + stderr)
as() { local u=$1; shift; docker exec -i -e REDISCLI_AUTH="$(pw "$u")" platform-redis redis-cli -p 4131 --user "$u" "$@" 2>&1; }
check() { # check "descrição" <esperado: ok|negado> <resposta>
  local desc=$1 want=$2 got=$3 denied=0
  grep -qE 'NOPERM|NOAUTH|WRONGPASS|ERR' <<<"$got" && denied=1
  if { [ "$want" = negado ] && [ "$denied" = 1 ]; } || { [ "$want" = ok ] && [ "$denied" = 0 ]; }; then
    printf '  ok     %s\n' "$desc"
  else
    printf '  FALHOU %s (resposta: %s)\n' "$desc" "$got"; fail=1
  fi
}

echo "isolamento entre produtos:"
check "A grava no próprio prefixo"              ok     "$(as selftest_a SET selftest_a:k 1)"
check "A lê o próprio prefixo"                  ok     "$(as selftest_a GET selftest_a:k)"
check "A não grava no prefixo de B"             negado "$(as selftest_a SET selftest_b:k 1)"
check "B não lê o prefixo de A"                 negado "$(as selftest_b GET selftest_a:k)"
check "A não publica no canal de B"             negado "$(as selftest_a PUBLISH selftest_b:ch x)"
check "A não lista chaves (KEYS)"               negado "$(as selftest_a KEYS '*')"
check "A não percorre chaves (SCAN)"            negado "$(as selftest_a SCAN 0)"
check "A não troca de banco (SELECT)"           negado "$(as selftest_a SELECT 1)"
check "A não apaga tudo (FLUSHALL)"             negado "$(as selftest_a FLUSHALL)"
check "A não altera a configuração (CONFIG)"    negado "$(as selftest_a CONFIG GET maxmemory)"
check "usuário default está desligado"          negado "$(docker exec platform-redis redis-cli -p 4131 PING 2>&1)"

[ "$fail" -eq 0 ] && echo "TUDO ISOLADO" || echo "ISOLAMENTO FALHOU"
exit "$fail"
