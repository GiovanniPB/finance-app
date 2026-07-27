# Finance — App de Finanças Pessoais

App **offline-first** (mobile + desktop first, web secundário) construído com
**Flutter + Supabase + PowerSync**. Este repositório é um **monorepo** (Melos +
Pub Workspaces) com a base de arquitetura, backend e quality gates prontos.

> Estado atual: **fundação** — sem UI de features. Há uma vertical slice
> *headless* (auth + accounts) provando o pipeline de dados.

## Stack

| Camada | Escolha |
|---|---|
| Framework | Flutter (via **FVM**, pinado em `3.44.6`) |
| Monorepo | Melos + Pub Workspaces |
| Estado/DI | Riverpod 3 + code generation |
| Sync offline | PowerSync (SQLite local ↔ Postgres) |
| Backend | Supabase (Postgres + Auth) |
| Roteamento | go_router (guard de auth) |
| Modelos | freezed + json_serializable |
| Erros | `Result`/`Failure` selados (`packages/core`) |
| Lints | very_good_analysis (strict, `--fatal-infos`) |
| Testes | flutter_test + mocktail (meta 80% cobertura) |

## Estrutura

```
apps/finance/        App: bootstrap, DI, router, features (data/domain/presentation)
packages/core/       Dart puro: Result/Failure, logger, env, extensions
packages/database/   Schema PowerSync, connector Supabase, ciclo de vida do DB
packages/design_system/  Tema e tokens
supabase/            Projeto Supabase CLI: migrations (schema + RLS + publication)
powersync/           sync_rules.yaml (buckets por usuário)
tool/                Scripts (ex.: gate de cobertura)
```

Decisões de arquitetura em [`docs/adr/`](docs/adr). Estado do projeto, o que já
está pronto e o que falta em [`docs/roadmap.md`](docs/roadmap.md).

## Pré-requisitos

- [FVM](https://fvm.app) · Docker · [Supabase CLI](https://supabase.com/docs/guides/cli)
- Melos: `fvm dart pub global activate melos`

## Setup

```bash
fvm install                 # instala o Flutter pinado (.fvmrc)
fvm dart pub get            # resolve o workspace (lockfile único na raiz)
fvm dart run build_runner build   # code generation (riverpod + freezed)
```

### Backend local

```bash
supabase start              # sobe Postgres + Auth locais (Docker) e aplica migrations
supabase status             # mostra URL/keys locais
```

> ⚠️ Se já houver outro stack Supabase local, ajuste as portas em
> `supabase/config.toml` (este projeto usa 553xx para coexistir).

Copie `env/example.json` para `env/dev.json` e preencha `SUPABASE_URL`,
`SUPABASE_ANON_KEY` (publishable key) e `POWERSYNC_URL`. Arquivos `env/*.json`
são git-ignored (exceto `example.json`).

### PowerSync

Ainda **não provisionado**. Crie uma instância (PowerSync Cloud ou self-hosted),
aponte-a para o Postgres do Supabase, publique `powersync/sync_rules.yaml` e
preencha `POWERSYNC_URL` no `env/<flavor>.json`.

## Rodando

```bash
fvm flutter run --flavor dev -t apps/finance/lib/main_dev.dart \
  --dart-define-from-file=env/dev.json
```

Flavors: `dev`, `staging`, `prod` (entrypoints `main_<flavor>.dart`).

## Comandos (Melos)

```bash
fvm dart run melos run analyze --no-select     # análise estática (fatal-infos)
fvm dart run melos run test --no-select        # testes de todos os pacotes
fvm dart run melos run coverage --no-select    # testes + lcov
fvm dart run melos run gen --no-select          # code generation
bash tool/check_coverage.sh 80                  # gate de cobertura (>= 80%)
```

## Qualidade

- CI em [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml): format → analyze
  → test + cobertura (gate 80%) → build web.
- Git hooks via `lefthook` (`lefthook install`): format + analyze no commit,
  testes no push.
- Código gerado (`*.g.dart`, `*.freezed.dart`) **não** é versionado — rode `gen`.

## Próximos passos

Fase atual: **fechar a Fase 0** — `categories`, `transactions` e `budgets`, mais
as telas de registro rápido, lista e home sobre o `design_system`.

O inventário completo (concluído, pendente, débitos técnicos e questões abertas)
está em [`docs/roadmap.md`](docs/roadmap.md).

Dois itens de ambiente que continuam bloqueando:

- **PowerSync não provisionado** — `POWERSYNC_URL` em `env/dev.json` ainda é um
  placeholder. Sem isso não há sincronização, e o teste de integração
  offline→online (inserir offline → reconectar → verificar no Postgres com RLS)
  não pode ser escrito.
- **Fontes não empacotadas** — destrava os golden tests do design system.
