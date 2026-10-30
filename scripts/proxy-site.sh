#!/usr/bin/env bash
# Liga ou desliga um conjunto de sites do proxy: platform/proxy/sites-disponiveis/<nome>.caddy <-> platform/proxy/sites/<nome>.caddy.
# Valida a configuração antes de recarregar; se falhar, desfaz e o proxy continua com a configuração anterior.
# Uso: scripts/proxy-site.sh enable|disable|status <nome>
set -euo pipefail
cd "$(dirname "$0")/.."
acao="${1:-}"; nome="${2:-}"
[[ "$acao" =~ ^(enable|disable|status)$ && "$nome" =~ ^[a-z0-9-]+$ ]] || { echo "uso: $0 enable|disable|status <nome>"; exit 2; }
dir=platform/proxy; origem="$dir/sites-disponiveis/$nome.caddy"; destino="$dir/sites/$nome.caddy"
proxy() { docker exec platform-proxy caddy "$@" --config /etc/caddy/Caddyfile; }

case "$acao" in
  status) [ -e "$destino" ] && echo "$nome: ligado" || echo "$nome: desligado" ;;
  enable)
    [ -f "$origem" ] || { echo "não existe $origem"; exit 1; }
    mkdir -p "$dir/sites"; cp "$origem" "$destino"
    if proxy validate >/dev/null && proxy reload; then echo "ok: $nome ligado"; else rm -f "$destino"; echo "configuração inválida: $nome NÃO foi ligado"; exit 1; fi ;;
  disable)
    rm -f "$destino"; proxy reload; echo "ok: $nome desligado" ;;
esac
