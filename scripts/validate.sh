#!/usr/bin/env bash
# Confere todo compose.yaml contra os padrões de docs/padroes.md, sem subir nada.
# A checagem é por serviço e está em scripts/validate.py (precisa de python3 e do docker compose 2.30+; não usa o daemon).
set -uo pipefail
cd "$(dirname "$0")/.."
for py in python3 python; do
  "$py" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null && exec "$py" scripts/validate.py
done
echo "python3 não encontrado"; exit 2
