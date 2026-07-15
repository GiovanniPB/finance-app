# Changelog

Este é o changelog agregado do workspace. Cada pacote também mantém o seu
próprio `CHANGELOG.md`. As entradas são geradas automaticamente por
`melos version` a partir dos [Conventional Commits](https://www.conventionalcommits.org).

## 0.1.0 — Base do projeto (2026-07-15)

Versão inicial (fundação, sem UI de features):

- Monorepo Melos + Pub Workspaces (Flutter via FVM 3.44.6).
- `packages/core`, `packages/database`, `packages/design_system` e `apps/finance`.
- Backend Supabase (migrations + RLS + publication) e sync rules do PowerSync.
- Vertical slice headless (auth + accounts) e quality gates (CI, cobertura 80%).

> A partir daqui, novas versões são criadas com `melos version --all` (ver
> [CONTRIBUTING](CONTRIBUTING.md#releases-e-versionamento)).
