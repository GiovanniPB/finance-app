# Finance — app de finanças pessoais colaborativo

App **offline-first** (mobile + desktop first, web secundário) em **Flutter +
Supabase + PowerSync**, num monorepo Melos + Pub Workspaces.

Unifica três experiências que hoje exigem apps separados: controle de gastos
individual, divisão de despesas em grupo e poupança gamificada. Mercado
brasileiro, com Open Finance e Pix nativos.

| Documento | Para quê |
|---|---|
| [`AGENTS.md`](AGENTS.md) | **como** trabalhar aqui: toolchain, escada de verificação, ciclo da fatia |
| [`docs/product.md`](docs/product.md) | domínio, invariantes, não-objetivos |
| [`docs/state.md`](docs/state.md) | onde estamos e quais são as próximas fatias |
| [`docs/surfaces.md`](docs/surfaces.md) | telas, navegação e componentes |
| [`docs/adr/`](docs/adr) | decisões caras de reverter, e seus porquês |

## Stack

| Camada | Escolha |
|---|---|
| Framework | Flutter (via **FVM**, pinado em `3.44.6`) |
| Monorepo | Melos + Pub Workspaces |
| Estado/DI | Riverpod 3 + code generation |
| Sync offline | PowerSync (SQLite local ↔ Postgres) |
| Backend | Supabase (Postgres + Auth + Edge Functions) |
| Open Finance | Pluggy, pipeline server-side ([ADR 0005](docs/adr/0005-open-finance-pluggy-server-side.md)) |
| Roteamento | go_router (guard de auth) |
| Modelos | freezed + json_serializable |
| Erros | `Result`/`Failure` selados (`packages/core`) |
| Lints | very_good_analysis (strict, `--fatal-infos`) |
| Testes | flutter_test + mocktail (gate de 80%) |

## Setup

```bash
fvm install                              # Flutter pinado (.fvmrc)
fvm dart pub get                         # resolve o workspace
fvm dart run melos run gen --no-select   # code generation (riverpod + freezed)
```

Copie `env/example.json` para `env/dev.json` e preencha `SUPABASE_URL`,
`SUPABASE_ANON_KEY` (publishable) e `POWERSYNC_URL`. Os `env/*.json` são
git-ignored.

## Rodando

Não precisa de Docker: o `env/dev.json` aponta para Supabase e PowerSync **na
nuvem**. O `supabase start` local existe para testar migration, não para rodar
o app.

```bash
cd apps/finance && fvm flutter run -d macos --target lib/main_dev.dart --dart-define-from-file=../../env/dev.json
```

Flavors: `dev`, `staging`, `prod` (entrypoints `main_<flavor>.dart`). Troque
`-d macos` por `-d iphone` para o simulador — lá o `--dart-define-from-file`
precisa de **caminho absoluto**.

## Comandos

```bash
fvm dart run melos run analyze --no-select    # análise estática (fatal-infos)
fvm dart run melos run test --no-select       # testes
fvm dart run melos run coverage --no-select   # testes + lcov
bash tool/check_coverage.sh 80                # gate de cobertura
bash tool/guards.sh                           # guardas de documento
tool/new-slice.sh <nome>                      # abre uma fatia
tool/close-slice.sh                           # fecha a fatia atual
```

A Definição de Pronto completa está em [`AGENTS.md`](AGENTS.md). O CI
(`.github/workflows/ci.yaml`) roda guardas → format → analyze → testes →
cobertura → integração (PowerSync real) → build web.

## Ambiente

| Alvo | Estado |
|---|---|
| macOS | ✅ roda |
| iOS Simulator | ✅ roda (Xcode 26.1.1) |
| Web (Chrome) | ⚠️ compila, mas falta `sqlite3.wasm` + worker em `apps/finance/web/` |
| Android | ⚠️ falta `cmdline-tools`, AVD e um `env/dev-android.json` (host `10.0.2.2` + cleartext) |
