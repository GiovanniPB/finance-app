# ADR 0002 — Acesso ao banco local: SQL bruto vs Drift

- Status: aceito
- Data: 2026-07-14

## Contexto

O PowerSync expõe um SQLite local. Há duas formas de consultá-lo em Flutter:
SQL bruto (`db.watch`/`db.execute`) ou a integração oficial com o ORM **Drift**
(queries type-safe verificadas em compile-time).

## Decisão

Usar **SQL bruto atrás de interfaces de repository**. A integração Drift↔PowerSync
ainda é marcada como **alpha**; para a base de um app financeiro priorizamos
estabilidade total na camada de dados.

Os repositories (`apps/finance/lib/features/<f>/data/`) recebem uma
`SqliteConnection` (interface implementada pelo `PowerSyncDatabase`), o que
mantém o domínio livre do SDK e permite testes com mocks.

## Consequências

- Camada de dados 100% em terreno estável e suportado.
- Queries em string não têm verificação de tipos — mitigado por testes e pelo
  mapeamento centralizado em `Account.fromRow`/`toColumns`.
- Migração futura para Drift é possível sem tocar em `domain`/`presentation`,
  quando a integração sair do alpha.
