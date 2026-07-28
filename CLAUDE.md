# CLAUDE.md — Guia operacional do projeto `finance-app`

Leia este arquivo antes de qualquer trabalho. Ele define **como** trabalhar neste
repositório. Para o "porquê" das decisões, veja [`docs/adr/`](docs/adr) e o
[`README.md`](README.md).

App de finanças pessoais **offline-first** (mobile + desktop first, web
secundário) em **Flutter + Supabase + PowerSync**, num **monorepo** Melos + Pub
Workspaces.

---

## 1. Toolchain — SEMPRE via FVM ⚠️

O Flutter é gerenciado por **FVM** e pinado em `.fvmrc` (`3.44.6`). **Nunca** use
`flutter`/`dart` diretamente — sempre com o prefixo `fvm`:

```bash
fvm flutter <cmd>
fvm dart <cmd>
fvm dart run melos <cmd>     # Melos roda como dev_dependency do workspace
```

Setup inicial numa máquina nova: `fvm install && fvm dart pub get`.

---

## 2. Comandos essenciais (Melos)

Rode da raiz. `--no-select` é obrigatório em execução não-interativa (CI/agente).

| Ação | Comando |
|---|---|
| Resolver deps | `fvm dart pub get` |
| Code generation | `fvm dart run melos run gen --no-select` |
| Formatar | `fvm dart format .` |
| Checar formatação | `fvm dart format --output=none --set-exit-if-changed .` |
| Análise estática | `fvm dart run melos run analyze --no-select` |
| Testes | `fvm dart run melos run test --no-select` |
| Testes + cobertura | `fvm dart run melos run coverage --no-select` |
| Gate de cobertura | `bash tool/check_coverage.sh 80` |
| Backend local | `supabase start` / `supabase status` / `supabase stop` |

---

## 3. Estrutura e onde colocar código

```
apps/finance/lib/
  bootstrap.dart · app.dart · main_<flavor>.dart   # composição (NÃO testados em unidade)
  di/providers.dart                                 # composition root (Riverpod)
  router/                                           # go_router + guard de auth
  features/<feature>/{domain,data,presentation}/    # features vivem aqui
packages/core/          # Dart puro: Result/Failure, logger, AppEnv, extensions
packages/database/      # schema PowerSync, SupabaseConnector, PowerSyncService
packages/design_system/ # tema, tokens, widgets base
supabase/migrations/    # SQL versionado (schema + RLS + publication)
powersync/sync_rules.yaml
tool/                   # scripts (ex.: gate de cobertura)
```

| O que | Onde |
|---|---|
| Utilitário transversal (Dart puro, sem Flutter) | `packages/core` |
| Persistência / sincronização | `packages/database` |
| Tema / widgets base reutilizáveis | `packages/design_system` |
| Nova feature | `apps/finance/lib/features/<feature>/` |

Features começam dentro do app e só são **promovidas a `packages/`** quando
estabilizam (não crie um pacote por feature prematuramente).

---

## 4. Regras de arquitetura (inegociáveis)

- **Camadas + fluxo unidirecional**: `presentation → domain ← data`.
  - `domain/`: entidades imutáveis (**freezed**), interfaces de repository, use
    cases (só quando houver regra de negócio real). **Nunca** importa Flutter,
    PowerSync ou Supabase.
  - `data/`: implementa as interfaces do domínio; mapeia linhas ↔ entidades na
    fronteira.
  - `presentation/`: providers/notifiers Riverpod.
- **Persistência**: SQL bruto do PowerSync (`watch`/`execute`) atrás de
  repositories que dependem de `SqliteConnection` (mockável). **Não** usar Drift
  (ver [ADR 0002](docs/adr/0002-persistencia-raw-sql-vs-drift.md)).
- **Erros**: retorne `Result<T, Failure>` (de `package:core`). Exceptions do SDK
  são convertidas em `Failure` na camada `data`; **nunca** vazam para a UI.
- **Estado/DI**: Riverpod 3 com **code generation** (`@riverpod`). Instâncias
  abertas em `bootstrap` são injetadas via `overrideWithValue`.
- **Imutabilidade**: `final`/`const` por padrão; `copyWith` para mudanças; nunca
  mutar objetos.
- **Modelos**: freezed + json_serializable.
- **Logs**: use `AppLogger` (redige segredos). Nunca `print`.

---

## 5. Backend local (Supabase + PowerSync)

- Este projeto roda o Supabase local em **portas 553xx** (offset +1000) para
  **coexistir** com outro stack Supabase da máquina (`finance-dashboard`).
  **Nunca** derrube o `finance-dashboard`.
- Toda tabela nova: PK `id`, `owner_id`, timestamps, **RLS obrigatório**
  (`owner_id = auth.uid()`), trigger de `updated_at`. Adicione ao schema local
  do PowerSync em `packages/database/lib/src/schema.dart` (a coluna `id` é
  implícita — não declarar).
- **Policy nova chama `private.is_space_member` / `private.has_space_role` /
  `private.is_space_owner`** — não `public.…`. As três vivem no schema `private`
  desde a migration `20260728030625` justamente para não virarem endpoint REST
  (o PostgREST expõe `public`, e função `SECURITY DEFINER` ali é chamável por
  `anon`). Função de apoio de RLS nasce em `private`; função de trigger pode
  ficar em `public`, mas com `revoke execute … from anon, authenticated, public`
  e `set search_path = ''`.
- Migrations: `supabase migration new <nome>` → editar SQL → `supabase db reset`
  para validar do zero. Rode `get_advisors` (segurança) após mudanças de schema.
- A publication `powersync` é `FOR ALL TABLES`; garanta `REPLICA IDENTITY FULL`
  em tabelas sincronizáveis.
- Sincronize `powersync/sync_rules.yaml` com o RLS (buckets por usuário).

---

## 6. Fluxo Git (branches, commits, PRs)

**Nunca** commite direto na `main` (exceto instrução explícita do usuário).

1. **Branch** a partir da `main` atualizada:
   `feat/<escopo>`, `fix/<escopo>`, `refactor/<escopo>`, `chore/<escopo>`,
   `docs/<escopo>`, `test/<escopo>`.
2. Commits em **Conventional Commits**: `feat: ...`, `fix: ...`, `refactor: ...`,
   `test: ...`, `docs: ...`, `chore: ...`, `perf: ...`, `ci: ...`.
   Mensagem no imperativo; corpo explicando o *porquê* quando útil.
3. **Antes de commitar**, rode a Definição de Pronto (seção 7).
4. Abra **PR para `main`**. Descreva mudanças + plano de teste. O **CI precisa
   passar** antes do merge. Não faça merge com CI vermelho ou conflitos.
5. Versionamento é automatizado via `melos version` (lê os Conventional Commits).

Não commite ações destrutivas ou irreversíveis sem confirmação do usuário.

---

## 7. Definição de Pronto (rode antes de commit/PR)

```bash
fvm dart run melos run gen --no-select        # 1. code generation
fvm dart format .                             # 2. formatação
fvm dart run melos run analyze --no-select    # 3. análise (zero infos/warnings)
fvm dart run melos run coverage --no-select   # 4. testes + cobertura
bash tool/check_coverage.sh 80                # 5. gate de cobertura >= 80%
```

Tudo precisa passar. `analyze` roda com `--fatal-infos --fatal-warnings`
(`very_good_analysis`): **zero** issues.

- **Testes**: TDD quando viável. Meta 80% na lógica de negócio (domain + data +
  state). Glue de sync/composição (bootstrap, entrypoints, `di/providers.dart`,
  `powersync_service.dart`, gerados) é excluído da métrica — cubra-o via testes
  de integração. Prefira **fakes**/mocktail; mocke `SqliteConnection` (não
  `PowerSyncDatabase`, que é `base`).

---

## 8. Segredos e configuração

- Config por flavor via `--dart-define-from-file=env/<flavor>.json`.
- `env/*.json` é **git-ignored** (exceto `env/example.json`). Nunca commite
  credenciais.
- No cliente use apenas a **publishable key** do Supabase; **nunca** a
  service-role/secret key.
- Chaves obrigatórias: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable),
  `POWERSYNC_URL`. Validadas em `AppEnv` (falha rápida no boot).

---

## 9. Code generation

Arquivos gerados (`*.g.dart`, `*.freezed.dart`) **não são versionados**. Sempre
rode `melos run gen` após clonar ou alterar anotações (`@riverpod`, `@freezed`).
Nunca edite arquivos gerados à mão.

---

## 10. Checklist — nova feature

1. `git switch -c feat/<nome>` a partir da `main`.
2. Crie `features/<nome>/{domain,data,presentation}/`.
3. Domain: entidade (freezed) + interface do repository.
4. Escreva testes (RED) → data: implementação → providers (GREEN).
5. Se houver tabela nova: migration + RLS + schema PowerSync + sync_rules.
6. Rode a Definição de Pronto (seção 7).
7. Commit(s) convencionais → PR para `main` com CI verde.
