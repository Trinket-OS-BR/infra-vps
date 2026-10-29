#!/usr/bin/env bash
# Prova que dois produtos não se enxergam no OpenObserve compartilhado: cria duas organizações e usuários temporários,
# tenta cruzar as fronteiras pela API e apaga os usuários no fim. As organizações `selftest_a` e `selftest_b` ficam
# (a edição de código aberto não as apaga); são vazias e reaproveitadas a cada execução.
# Sai com código diferente de 0 se algum isolamento falhar. Uso: scripts/observability-selftest.sh
set -uo pipefail
c=${O2_CONTAINER:-platform-openobserve}
fail=0
J='Content-Type: application/json'

root() { # root <método> <caminho> [corpo]
  printf '%s' "${3:-}" | docker exec -i "$c" sh -c \
    'curl -sS -X "$0" -u "$ZO_ROOT_USER_EMAIL:$ZO_ROOT_USER_PASSWORD" -H "Content-Type: application/json" --data-binary @- "http://localhost:4140$1"' "$1" "$2"
}
as() { # as <email> <senha> <método> <caminho> [corpo]: devolve "<corpo> [código]"
  printf '%s' "${5:-}" | docker exec -i "$c" sh -c \
    'curl -sS -X "$2" -u "$0:$1" -H "Content-Type: application/json" --data-binary @- -w " [%{http_code}]" "http://localhost:4140$3"' "$1" "$2" "$3" "$4"
}
orgid() { # orgid <nome>: cria a organização se faltar e devolve o identificador
  local id
  id=$(root GET /api/organizations | tr '{' '\n' | grep "\"name\":\"$1\"" | sed -n 's/.*"identifier":"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$id" ] || id=$(root POST /api/organizations "{\"name\":\"$1\"}" | sed -n 's/.*"identifier":"\([^"]*\)".*/\1/p')
  echo "$id"
}
check() { # check "descrição" <ok|negado> <regex de sucesso> <resposta>
  local desc=$1 want=$2 re=$3 got=$4 hit=0
  grep -qE "$re" <<<"$got" && hit=1
  if { [ "$want" = ok ] && [ "$hit" = 1 ]; } || { [ "$want" = negado ] && [ "$hit" = 0 ]; }; then
    printf '  ok     %s\n' "$desc"
  else
    printf '  FALHOU %s (resposta: %s)\n' "$desc" "$(tr '\n' ' ' <<<"$got" | cut -c1-120)"; fail=1
  fi
}

A=$(orgid selftest_a); B=$(orgid selftest_b)
[ -n "$A" ] && [ -n "$B" ] || { echo "não consegui preparar as organizações de teste"; exit 1; }
UA="selftest_a@ingest.invalid"; UB="selftest_b@ingest.invalid"
PA="Aa1!$(openssl rand -hex 12)"; PB="Aa1!$(openssl rand -hex 12)"
cleanup() { root DELETE "/api/$A/users/$UA" >/dev/null 2>&1; root DELETE "/api/$B/users/$UB" >/dev/null 2>&1; }
trap cleanup EXIT
cleanup
root POST "/api/$A/users" "{\"email\":\"$UA\",\"password\":\"$PA\",\"first_name\":\"a\",\"last_name\":\"t\",\"role\":\"admin\"}" >/dev/null
root POST "/api/$B/users" "{\"email\":\"$UB\",\"password\":\"$PB\",\"first_name\":\"b\",\"last_name\":\"t\",\"role\":\"admin\"}" >/dev/null

echo "isolamento entre produtos:"
check "A envia logs para a própria organização"      ok     '\[200\]' "$(as "$UA" "$PA" POST "/api/$A/teste/_json" '[{"m":"ola"}]')"
check "A envia OTLP para a própria organização"      ok     '\[200\]' "$(as "$UA" "$PA" POST "/api/$A/v1/logs" '{"resourceLogs":[]}')"
check "B envia logs para a própria organização"      ok     '\[200\]' "$(as "$UB" "$PB" POST "/api/$B/teste/_json" '[{"m":"ola"}]')"
check "A não escreve na organização de B"            negado '\[200\]' "$(as "$UA" "$PA" POST "/api/$B/teste/_json" '[{"m":"x"}]')"
check "B não escreve na organização de A"            negado '\[200\]' "$(as "$UB" "$PB" POST "/api/$A/teste/_json" '[{"m":"x"}]')"
check "A não lê os streams de B"                     negado '\[200\]' "$(as "$UA" "$PA" GET "/api/$B/streams")"
check "A não lista os usuários de B"                 negado '\[200\]' "$(as "$UA" "$PA" GET "/api/$B/users")"
check "A não cria usuário na organização de B"       negado '\[200\]' "$(as "$UA" "$PA" POST "/api/$B/users" '{"email":"x@ingest.invalid","password":"Aa1!xxxxxxxx","first_name":"x","last_name":"x","role":"admin"}')"
check "A não lê a organização default"               negado '\[200\]' "$(as "$UA" "$PA" GET "/api/default/streams")"
check "senha errada é recusada"                      negado '\[200\]' "$(as "$UA" "errada" POST "/api/$A/teste/_json" '[{"m":"x"}]')"
check "sem credencial é recusado"                    negado '\[200\]' "$(docker exec "$c" curl -sS -w ' [%{http_code}]' "http://localhost:4140/api/$A/streams" </dev/null)"

[ "$fail" -eq 0 ] && echo "TUDO ISOLADO" || echo "ISOLAMENTO FALHOU"
exit "$fail"
