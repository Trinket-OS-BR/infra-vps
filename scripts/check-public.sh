#!/usr/bin/env bash
# Este repositório é público: nenhum endereço IP real, chave privada ou token pode estar em arquivo versionado.
# Confere só o que o Git rastreia. Não substitui a revisão humana; pega o descuido mais comum.
# Uso: scripts/check-public.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# IPv4 literal, fora os de uso local e de documentação (RFC 5737) e as faixas privadas do Docker em exemplos.
ips=$(git grep -nIE '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)' -- . ':!*.svg' |
  grep -vE '(^|[^0-9.])(127\.0\.0\.1|0\.0\.0\.0|192\.0\.2\.[0-9]+|198\.51\.100\.[0-9]+|203\.0\.113\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)([^0-9.]|$)' || true)
if [ -n "$ips" ]; then fail=1; echo "FALHA  endereço IP em arquivo versionado:"; printf '%s\n' "$ips" | cut -c1-160 | sed 's/^/         /'; fi

# Chaves privadas e tokens com formato conhecido.
segredos=$(git grep -nIE -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -e 'gh[pousr]_[A-Za-z0-9]{30,}' -e 'github_pat_[A-Za-z0-9_]{30,}' \
  -e 'AKIA[0-9A-Z]{16}' -e 'sk_live_[A-Za-z0-9]{20,}' -- . ':!scripts/check-public.sh' || true)
if [ -n "$segredos" ]; then fail=1; echo "FALHA  possível segredo em arquivo versionado:"; printf '%s\n' "$segredos" | cut -d: -f1,2 | sed 's/^/         /'; fi

# Só os modelos (*.example) de .env podem ser versionados.
envs=$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v '\.example$' || true)
if [ -n "$envs" ]; then fail=1; echo "FALHA  arquivo .env versionado:"; printf '%s\n' "$envs" | sed 's/^/         /'; fi

[ "$fail" = 0 ] && echo "OK     nenhum endereço IP, chave ou .env real nos arquivos versionados"
exit $fail
