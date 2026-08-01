#!/usr/bin/env bash
# Abre uma fatia: valida os portões, cria o branch e o contrato.
set -euo pipefail

nome="${1:-}"
tipo="${2:-feat}"

if [ -z "$nome" ]; then
  echo "uso: tool/new-slice.sh <nome-em-kebab> [feat|fix|chore|docs|test|perf]" >&2
  exit 1
fi

# Portão 1 — a Fase 0 existe
if [ ! -f docs/product.md ]; then
  echo "erro: docs/product.md não existe. Rode a Fase 0 antes de fatiar." >&2
  exit 1
fi

# Portão 2 — uma fatia por vez (é o que sustenta o dimensionamento)
abertos=$(find docs/slices -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$abertos" -ne 0 ]; then
  echo "erro: já existe contrato aberto:" >&2
  ls docs/slices/*.md >&2
  echo "feche a fatia atual com tool/close-slice.sh antes de abrir outra." >&2
  exit 1
fi

# Portão 3 — árvore limpa, partindo da main atualizada
if [ -n "$(git status --porcelain)" ]; then
  echo "erro: árvore suja. Commite ou descarte antes de abrir fatia." >&2
  exit 1
fi

# Portão 4 — nenhum PR aberto para a main.
#
# O portão 2 sozinho não basta: close-slice.sh apaga o contrato ANTES do merge,
# e nessa janela a fatia seguinte nasceria de uma main que não tem a anterior.
# Achado em uso real (flutter-app): feat/cadastro-manual saiu sem a fatia
# entrar dentro.
if command -v gh >/dev/null 2>&1; then
  pr_abertos=$(gh pr list --state open --base main --json number,headRefName \
    --jq '.[] | "  #\(.number) \(.headRefName)"' 2>/dev/null || true)
  if [ -n "$pr_abertos" ]; then
    echo "erro: existe PR aberto para a main:" >&2
    echo "$pr_abertos" >&2
    echo "mergeie antes de abrir fatia, senão a nova nasce sem a anterior." >&2
    exit 1
  fi
fi

# A base é `origin/main`, nunca a `main` local. A local costuma estar atrás, e
# ramificar dela gera PR com conflito e trabalho refeito.
if git remote get-url origin >/dev/null 2>&1; then
  git fetch origin -q
  git switch -c "${tipo}/${nome}" origin/main -q
else
  echo "aviso: sem remoto, ramificando da main local"
  git switch -c "${tipo}/${nome}" main -q
fi

mkdir -p docs/slices
sed "s/{{nome}}/${nome}/g" docs/.templates/slice.md > "docs/slices/${nome}.md"

echo "fatia aberta: ${tipo}/${nome}"
echo "contrato:     docs/slices/${nome}.md"
echo
echo "próximo passo: preencher o contrato ANTES de abrir código."
echo "se o \"pronto quando\" precisar da palavra \"e\", quebre em duas fatias."
