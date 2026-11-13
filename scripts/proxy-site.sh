#!/usr/bin/env bash
# Liga ou desliga um conjunto de sites do proxy: platform/proxy/sites-disponiveis/<nome>.caddy <-> platform/proxy/sites/<nome>.caddy.
# Valida a configuração antes de recarregar; se falhar, desfaz e o proxy continua com a configuração anterior.
# O site ligado é uma CÓPIA: depois de um `git pull` que mude sites-disponiveis/, rode `sync` para a mudança valer.
# Uso: scripts/proxy-site.sh enable|disable|status <nome>
#      scripts/proxy-site.sh sync      reaplica os sites já ligados a partir de sites-disponiveis/
#      scripts/proxy-site.sh list      mostra os sites ligados e se estão iguais ao modelo
set -euo pipefail
cd "$(dirname "$0")/.."
acao="${1:-}"; nome="${2:-}"
uso() { echo "uso: $0 enable|disable|status <nome>  |  $0 sync|list"; exit 2; }
case "$acao" in
  sync|list) [ -z "$nome" ] || uso ;;
  enable|disable|status) [[ "$nome" =~ ^[a-z0-9-]+$ ]] || uso ;;
  *) uso ;;
esac
dir=platform/proxy; origem="$dir/sites-disponiveis/$nome.caddy"; destino="$dir/sites/$nome.caddy"
proxy() { docker exec platform-proxy caddy "$@" --config /etc/caddy/Caddyfile; }
ligados() { find "$dir/sites" -maxdepth 1 -name '*.caddy' 2>/dev/null | sort; }

case "$acao" in
  status) [ -e "$destino" ] && echo "$nome: ligado" || echo "$nome: desligado" ;;
  list)
    for f in $(ligados); do
      n=$(basename "$f" .caddy); o="$dir/sites-disponiveis/$n.caddy"
      if [ ! -f "$o" ]; then echo "$n: ligado, sem modelo em sites-disponiveis/"
      elif cmp -s "$o" "$f"; then echo "$n: ligado, igual ao modelo"
      else echo "$n: ligado, DIFERENTE do modelo (rode sync)"; fi
    done ;;
  enable)
    [ -f "$origem" ] || { echo "não existe $origem"; exit 1; }
    mkdir -p "$dir/sites"; cp "$origem" "$destino"
    if proxy validate >/dev/null && proxy reload; then echo "ok: $nome ligado"; else rm -f "$destino"; echo "configuração inválida: $nome NÃO foi ligado"; exit 1; fi ;;
  disable)
    rm -f "$destino"; proxy reload; echo "ok: $nome desligado" ;;
  sync)
    copia=$(mktemp -d); trap 'rm -rf "$copia"' EXIT
    mudou=()
    for f in $(ligados); do
      n=$(basename "$f" .caddy); o="$dir/sites-disponiveis/$n.caddy"
      [ -f "$o" ] || { echo "aviso: $n está ligado, mas não existe mais em sites-disponiveis/ (mantido como está)"; continue; }
      cmp -s "$o" "$f" && continue
      cp "$f" "$copia/$n.caddy"; cp "$o" "$f"; mudou+=("$n")
    done
    [ ${#mudou[@]} -gt 0 ] || { echo "nada a sincronizar"; exit 0; }
    if proxy validate >/dev/null && proxy reload; then echo "ok: sincronizado(s): ${mudou[*]}"
    else
      for n in "${mudou[@]}"; do cp "$copia/$n.caddy" "$dir/sites/$n.caddy"; done
      echo "configuração inválida: nada foi alterado (${mudou[*]} voltaram ao que estava)"; exit 1
    fi ;;
esac
