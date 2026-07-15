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

## Releases e versionamento

O versionamento é automatizado pelo Melos a partir dos **Conventional Commits**
(por isso a disciplina de commits importa). Cada pacote é versionado de forma
independente e recebe a sua própria tag (ex.: `core-v0.2.0`).

Regras de bump (semver): `fix:` → patch · `feat:` → minor · `!`/`BREAKING
CHANGE` → major. `docs:`/`chore:`/`ci:`/`test:` não geram release.

### Como criar um release

Preferencialmente pelo workflow **Release (version)** no GitHub Actions
(`workflow_dispatch`), que roda na `main`, versiona, gera CHANGELOGs, cria as
tags e faz push. Use o input `dry_run` para pré-visualizar sem commitar.

Localmente (a partir da `main` atualizada):

```bash
fvm dart run melos version --all        # --all inclui os pacotes privados
git push --follow-tags origin main
```

> `--all` é necessário porque todos os pacotes são `publish_to: none`
> (privados) — o Melos os pularia por padrão. Nada é publicado no pub.dev.

Build e distribuição de artefatos (Android/iOS/web, lojas, OTA) são um passo
futuro (Nível 2), a ser adicionado quando houver app publicável.
