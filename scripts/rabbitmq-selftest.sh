#!/usr/bin/env bash
# Prova que dois produtos não se enxergam no RabbitMQ compartilhado: cria dois vhosts e usuários
# temporários, tenta cruzar as fronteiras por STOMP e pela API de gestão e apaga tudo no fim.
# Sai com código diferente de 0 se algum isolamento falhar. Uso: scripts/rabbitmq-selftest.sh
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); fail=0
ctl() { docker exec platform-rabbitmq rabbitmqctl --quiet "$@" </dev/null; }
cleanup() {
  for u in selftest_a selftest_b; do ctl delete_user "$u" >/dev/null 2>&1; ctl delete_vhost "$u" >/dev/null 2>&1; done
  rm -rf "$tmp"
}
trap cleanup EXIT

for u in selftest_a selftest_b; do
  scripts/rabbitmq-create-vhost.sh "$u" "$tmp/$u.env" >/dev/null </dev/null || { echo "não consegui criar $u"; exit 1; }
done
pw() { sed -n 's#^RABBITMQ_PASSWORD=##p' "$tmp/$1.env"; }

# stomp <login> <senha> <vhost> [frames extras]: devolve o que o broker respondeu (CONNECTED, RECEIPT ou ERROR)
stomp() {
  { printf 'CONNECT\nlogin:%s\npasscode:%s\nhost:%s\naccept-version:1.2\n\n\0' "$1" "$2" "$3"; printf '%b' "${4:-}"; sleep 1; } \
    | docker exec -i platform-rabbitmq nc -w 3 127.0.0.1 4133 2>&1 | tr -d '\0'
}
# api <usuário> <caminho>: devolve a resposta da API de gestão (ou o erro HTTP)
api() {
  local auth; auth=$(printf '%s:%s' "$1" "$(pw "$1")" | base64 | tr -d '\n')
  docker exec platform-rabbitmq wget -qO- --header="Authorization: Basic $auth" "http://127.0.0.1:4134$2" 2>&1 </dev/null
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

echo "isolamento entre produtos (STOMP):"
check "A conecta no próprio vhost"            ok     'CONNECTED' "$(stomp selftest_a "$(pw selftest_a)" selftest_a)"
check "A envia e recebe confirmação"          ok     'RECEIPT'   "$(stomp selftest_a "$(pw selftest_a)" selftest_a 'SEND\ndestination:/queue/teste\nreceipt:r1\n\nola\0')"
check "A não conecta no vhost de B"           negado 'CONNECTED' "$(stomp selftest_a "$(pw selftest_a)" selftest_b)"
check "B não conecta no vhost de A"           negado 'CONNECTED' "$(stomp selftest_b "$(pw selftest_b)" selftest_a)"
check "A não conecta no vhost padrão (/)"     negado 'CONNECTED' "$(stomp selftest_a "$(pw selftest_a)" /)"
check "senha errada é recusada"               negado 'CONNECTED' "$(stomp selftest_a errada selftest_a)"
check "usuário guest não existe"              negado 'CONNECTED' "$(stomp guest guest /)"

echo "API de gestão sem etiqueta (padrão do produto):"
check "A não entra na API de gestão"          negado '\[' "$(api selftest_a /api/queues/selftest_a)"

# Com a etiqueta `management` (opcional, para o produto ver as próprias filas no painel) o isolamento continua.
ctl set_user_tags selftest_a management >/dev/null 2>&1
echo "API de gestão com a etiqueta management:"
check "A lê as filas do próprio vhost"        ok     '\[' "$(api selftest_a /api/queues/selftest_a)"
check "A não lê as filas de B"                negado '\[' "$(api selftest_a /api/queues/selftest_b)"
check "A não lista usuários"                  negado '"name"' "$(api selftest_a /api/users)"
check "A não vê o vhost de B na lista"        negado 'selftest_b' "$(api selftest_a /api/vhosts)"

[ "$fail" -eq 0 ] && echo "TUDO ISOLADO" || echo "ISOLAMENTO FALHOU"
exit "$fail"
