# ADR 0006 — Política de dinheiro (inteiros em unidades mínimas)

- Status: aceito
- Data: 2026-07-17

## Contexto

Valores monetários atravessam Postgres → PowerSync → SQLite local → Dart. O
PowerSync não tem tipo `numeric`/`decimal`: números viram `REAL` (ponto flutuante
IEEE-754) no SQLite local. Guardar dinheiro como `double` introduz erro de
arredondamento acumulável — inaceitável em um app financeiro. A Pluggy, por sua
vez, entrega valores como `number` (double, em unidades da moeda).

## Decisão

**Dinheiro é sempre inteiro em unidades mínimas** (centavos para BRL) ponta a
ponta:

- **Postgres**: `amount_minor bigint not null` (+ `currency text` ISO-4217).
- **Sync/local**: inteiro trafega sem perda (o PowerSync preserva inteiros).
- **Dart**: value object `Money` em `packages/core` encapsula `amountMinor` (int)
  + `currency`. Toda aritmética é inteira.

A conversão do `double` da Pluggy para `amount_minor` acontece **uma única vez**,
na borda de ingestão (Edge Function), com arredondamento explícito
(`round(value * 100)`), nunca no cliente.

## Consequências

- Zero erro de ponto flutuante em qualquer soma/split/orçamento.
- `Money` centraliza formatação (`R$ 1.234,56`), parsing e operações; a UI e o
  domínio nunca manipulam centavos crus.
- Colunas monetárias em todas as tabelas seguem o sufixo `_minor` (ex.:
  `amount_minor`, `target_amount_minor`, `current_amount_minor`).
- Split e "quem deve a quem" operam em inteiros → a soma das partes fecha exato
  (resto de divisão distribuído deterministicamente).

## Alternativas descartadas

- **`numeric` no PG + `Decimal` no Dart**: correto no servidor, mas o PowerSync
  materializa como texto/real localmente; exigiria mapeamento cuidadoso em cada
  query e reabriria a porta do float. Mais superfície de erro.
- **`double`**: descartado por definição (erro de arredondamento).
