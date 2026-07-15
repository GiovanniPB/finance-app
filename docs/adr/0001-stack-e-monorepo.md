# ADR 0001 — Stack e monorepo

- Status: aceito
- Data: 2026-07-14

## Contexto

App de finanças pessoais offline-first, mobile + desktop first (web secundário),
que precisa escalar em organização e time.

## Decisão

- **Flutter** (via FVM, versão pinada `3.44.6`) como framework multiplataforma.
- **Supabase** (Postgres + Auth) como backend e **PowerSync** para sincronização
  offline-first (SQLite local ↔ Postgres).
- **Monorepo** com **Melos + Pub Workspaces**: `apps/` + `packages/`, resolução
  única de dependências (lockfile na raiz).
- **Riverpod 3 + code generation** para estado e injeção de dependências.
- Concerns transversais (`core`, `database`, `design_system`) como **pacotes**;
  features começam dentro de `apps/finance/lib/features/` e são promovidas a
  pacotes quando estabilizam (evita fragmentação prematura).

## Consequências

- Fronteiras fortes e testáveis; onboarding e refatoração mais seguros.
- Uma toolchain única (FVM) e um pipeline de qualidade compartilhado.
- Custo: setup inicial de monorepo e code generation.
