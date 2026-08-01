#!/usr/bin/env bash
# Guardas de documentação. Roda local e no CI.
# Impedem exatamente o modo de falha conhecido: documento vivo virar diário.
set -uo pipefail

falhou=0

# 1. state.md não pode virar diário
#
# Faixa, e não número seco. Um teto apertado cobra o imposto no pior momento —
# no fechamento da fatia, quando o que falta é abrir o PR — e o trabalho vira
# recortar frase útil para caber. O que o guarda precisa impedir é o documento
# CRESCER SEM FIM, não ele passar de um número exato.
#
#   até AVISO      silêncio
#   AVISO..FALHA   avisa e deixa passar: a próxima reescrita corta
#   acima de FALHA falha — aí já é diário, não estado
AVISO=180
FALHA=240

if [ -f docs/state.md ]; then
  linhas=$(wc -l < docs/state.md | tr -d ' ')
  if [ "$linhas" -gt "$FALHA" ]; then
    echo "FALHA: docs/state.md tem ${linhas} linhas (limite ${FALHA})."
    echo "       Ele é reescrito, não acumulado. Histórico vive no git log."
    falhou=1
  elif [ "$linhas" -gt "$AVISO" ]; then
    echo "aviso: docs/state.md tem ${linhas} linhas (confortável até ${AVISO})."
    echo "       Não falha. Na próxima reescrita, corte o que o git log já guarda."
  fi
fi

# 2. histórico não se duplica em markdown
# Radicais SEM acento de propósito: [ií] em expressão de colchetes não casa o
# caractere multibyte quando LANG está vazio, e o padrão precisa de -i.
DIARIO='^#+.*(conclu|hist|changelog|feito em|entregue em)'
if grep -rqiE "$DIARIO" docs/state.md docs/surfaces.md 2>/dev/null; then
  echo "FALHA: seção de histórico em documento vivo:"
  grep -rniE "$DIARIO" docs/state.md docs/surfaces.md 2>/dev/null | sed 's/^/       /'
  echo "       Remova. git log já responde isso."
  falhou=1
fi

# 3. não pode dar MERGE com contrato aberto — mas push durante o trabalho é
#    legítimo e não pode ficar vermelho. Por isso este guarda é opt-in:
#    o CI só liga FATIA_GATE=1 quando o PR sai de draft (passo 5).
#    Vermelho previsível ensina a ignorar vermelho.
if [ "${FATIA_GATE:-}" = "1" ]; then
  abertos=$(find docs/slices -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$abertos" -ne 0 ]; then
    echo "FALHA: contrato de fatia ainda aberto:"
    ls docs/slices/*.md | sed 's/^/       /'
    echo "       Rode tool/close-slice.sh antes de marcar o PR como pronto."
    falhou=1
  fi
fi

if [ "$falhou" -eq 0 ]; then
  echo "guardas: ok"
fi
exit "$falhou"
