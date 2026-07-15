#!/usr/bin/env bash
# Agrega todos os lcov.info do workspace e falha se a cobertura de linhas total
# ficar abaixo do limite. Uso: tool/check_coverage.sh [limite_percentual]
# Portável (bash 3.2+/macOS): usa apenas find + awk.
#
# Exclui da métrica: código gerado (.g.dart, .freezed.dart) e glue de
# composição não testável em unidade (entrypoints de flavor, bootstrap).
set -euo pipefail

THRESHOLD="${1:-80}"

files=$(find apps packages -type f -name 'lcov.info' 2>/dev/null || true)
if [ -z "$files" ]; then
  echo "Nenhum lcov.info encontrado — rode os testes com --coverage antes." >&2
  exit 1
fi

# shellcheck disable=SC2086
summary=$(cat $files | awk -F: -v t="$THRESHOLD" '
  # Exclui: gerado, entrypoints, bootstrap, composition root e glue de sync
  # que só é exercido em teste de integração (PowerSync ao vivo).
  /^SF:/ {
    skip = ($0 ~ "\\.g\\.dart$" || $0 ~ "\\.freezed\\.dart$" \
      || $0 ~ "/main_[^/]*\\.dart$" || $0 ~ "/bootstrap\\.dart$" \
      || $0 ~ "/di/providers\\.dart$" || $0 ~ "/powersync_service\\.dart$") \
      ? 1 : 0
  }
  /^LH:/ { if (!skip) h += $2 }
  /^LF:/ { if (!skip) f += $2 }
  END {
    if (f == 0) { print "0 0 0 1"; exit }
    pct = (h / f) * 100
    printf "%.2f %d %d %d", pct, h, f, (pct < t) ? 1 : 0
  }')

pct=$(echo "$summary" | cut -d' ' -f1)
hit=$(echo "$summary" | cut -d' ' -f2)
found=$(echo "$summary" | cut -d' ' -f3)
below=$(echo "$summary" | cut -d' ' -f4)

echo "Cobertura total: ${pct}% (${hit}/${found} linhas) — limite ${THRESHOLD}%"
if [ "$below" -eq 1 ]; then
  echo "❌ Cobertura abaixo do limite de ${THRESHOLD}%." >&2
  exit 1
fi
echo "✅ Cobertura acima do limite."
