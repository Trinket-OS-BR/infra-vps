#!/usr/bin/env bash
# Confere todo compose.yaml contra os padrões de docs/padroes.md, sem subir nada.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
created=()

for f in $(find platform apps -name compose.yaml 2>/dev/null | sort); do
  problems=()
  have() { grep -qE "$1" "$f"; }
  have '^\s+container_name:'        || problems+=("sem container_name")
  have '^\s+restart: unless-stopped' || problems+=("sem restart: unless-stopped")
  have '^\s+healthcheck:'           || have '# healthcheck: definido no Dockerfile' || problems+=("sem healthcheck")
  have '^\s+mem_limit:'             || problems+=("sem mem_limit")
  have '^\s+cpus:'                  || problems+=("sem cpus")
  have '^\s+pids_limit:'            || problems+=("sem pids_limit")
  have 'no-new-privileges:true'     || problems+=("sem no-new-privileges")
  have 'max-size'                   || problems+=("sem rotação de logs")
  have 'app\.product:'              || problems+=("sem rótulo app.product")
  have ':latest'                    && problems+=("usa :latest")
  have '^\s+ports:'                 && ! [[ "$f" == platform/proxy/* ]] && problems+=("publica porta no host")
  have ':-(admin|password|senha)'   && problems+=("senha padrão no compose")
  # todo serviço de plataforma precisa constar no diagrama (apps seguem o padrão genérico do nó "app")
  if [[ "$f" == platform/* ]]; then
    svc=$(echo "$f" | awk -F/ '{print $2}')
    grep -qiw "$svc" docs/diagrama.md 2>/dev/null || problems+=("serviço \"$svc\" não consta em docs/diagrama.md")
  fi
  dir=$(dirname "$f"); tmp=0
  for e in .env .env.production; do
    grep -q "$e" "$f" && [ ! -e "$dir/$e" ] && { : > "$dir/$e"; tmp=1; created+=("$dir/$e"); }
  done
  (cd "$dir" && IMAGE_TAG=validate docker compose config --quiet 2>/dev/null) || problems+=("docker compose config falhou (ou docker parado)")
  [ "$tmp" = 1 ] && { rm -f "${created[@]}"; created=(); }
  if [ ${#problems[@]} -eq 0 ]; then echo "OK     $f"; else fail=1; echo "FALHA  $f"; printf '         - %s\n' "${problems[@]}"; fi
done
exit $fail
