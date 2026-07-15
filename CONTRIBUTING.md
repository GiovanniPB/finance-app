# Contribuindo

## Fluxo

1. Branch a partir de `main`.
2. Desenvolva seguindo a arquitetura em camadas (ver [ADRs](docs/adr)).
3. Rode localmente antes de abrir PR:
   ```bash
   fvm dart run melos run gen --no-select
   fvm dart format .
   fvm dart run melos run analyze --no-select
   fvm dart run melos run coverage --no-select && bash tool/check_coverage.sh 80
   ```
4. Abra o PR — o CI precisa passar (format, analyze, testes, cobertura, build).

## Convenções

- **Commits**: [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`, `perf:`, `ci:`).
  O versionamento é automatizado via `melos version`.
- **Camadas**: `presentation → domain ← data`. `domain` não importa Flutter,
  PowerSync ou Supabase.
- **Imutabilidade**: entidades com freezed; nunca mutar objetos.
- **Erros**: retorne `Result<T, Failure>`; não deixe exceptions vazarem para a UI.
- **Estado**: Riverpod 3 com code generation (`@riverpod`).
- **Testes**: TDD quando possível; cobertura mínima de 80% (lógica de negócio).
- **Lints**: `very_good_analysis` com `--fatal-infos` — zero warnings/infos.

## Onde colocar código

| Tipo | Local |
|---|---|
| Utilitário transversal (Dart puro) | `packages/core` |
| Persistência / sync | `packages/database` |
| Tema / widgets base | `packages/design_system` |
| Feature (data/domain/presentation) | `apps/finance/lib/features/<feature>` |

Features estabilizadas podem ser promovidas a pacotes em `packages/`.
