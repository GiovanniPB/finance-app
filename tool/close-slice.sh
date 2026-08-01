#!/usr/bin/env bash
# Fecha a fatia: roda os guardas, resume o que mudou e apaga o contrato.
# Não interativo de propósito — quem reescreve o state.md é o agente.
set -euo pipefail

contrato=$(find docs/slices -maxdepth 1 -name '*.md' 2>/dev/null | head -1)
if [ -z "$contrato" ]; then
  echo "erro: nenhum contrato aberto em docs/slices/." >&2
  exit 1
fi
nome=$(basename "$contrato" .md)

echo "=== fatia: ${nome} ==="
echo
echo "--- pronto quando (do contrato) ---"
sed -n '/^## Pronto quando/,/^## /p' "$contrato" | sed '1d;/^## /d' | sed '/^$/d'
echo
echo "--- o que mudou nesta fatia ---"
base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo "")
if [ -n "$base" ]; then
  git diff --shortstat "$base"..HEAD
  echo
  echo "arquivos:"
  git diff --name-only "$base"..HEAD | sed 's/^/  /'
else
  echo "  (não achei merge-base com main)"
fi
echo
echo "--- tamanho da fatia ---"
if [ -n "$base" ]; then
  ins=$(git diff --shortstat "$base"..HEAD | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
  arq=$(git diff --name-only "$base"..HEAD | wc -l | tr -d ' ')
  echo "  ${ins} linhas inseridas, ${arq} arquivos"
  if [ "${ins:-0}" -gt 2500 ] || [ "${arq:-0}" -gt 25 ]; then
    echo "  AVISO: acima da faixa saudável (800–1800 linhas, ~20 arquivos)."
    echo "  Registre em state.md que esta fatia foi grande, e por quê."
  fi
fi
echo
rm -f "$contrato"
echo "contrato apagado (o git log é o arquivo morto)."
echo
echo "PENDENTE — o agente faz agora:"
echo "  1. reescrever docs/state.md (onde estamos · última fatia · próximas 3)"
echo "  2. ADR em docs/adr/ se alguma decisão cara foi tomada nesta fatia"
echo "  3. atualizar docs/surfaces.md se nasceu tela ou componente"
echo "  4. rodar tool/guards.sh"
