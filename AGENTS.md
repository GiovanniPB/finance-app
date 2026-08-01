# AGENTS.md — finance-app

App de finanças pessoais **offline-first** (mobile + desktop first, web
secundário) em **Flutter + Supabase + PowerSync**, num monorepo Melos + Pub
Workspaces.

O "porquê" das decisões está em [`docs/adr/`](docs/adr); o domínio e os
invariantes em [`docs/product.md`](docs/product.md); as telas em
[`docs/surfaces.md`](docs/surfaces.md).

## Abertura de sessão

Leia **três arquivos e só três**: este, [`docs/state.md`](docs/state.md), e o
contrato da fatia em `docs/slices/`. **Não abra código antes de o contrato estar
fechado** — a exploração é a parte imprevisível do orçamento de contexto.

Se você precisar de algo que não está no repo, isso é um buraco do método:
escreva no lugar certo em vez de pedir ao usuário para reexplicar.

## Toolchain — sempre via FVM ⚠️

O Flutter é gerenciado por **FVM** e pinado em `.fvmrc` (`3.44.6`). **Nunca** use
`flutter`/`dart` direto:

```bash
fvm flutter <cmd>
fvm dart <cmd>
fvm dart run melos <cmd>     # Melos é dev_dependency do workspace
```

Máquina nova: `fvm install && fvm dart pub get`. Arquivos gerados
(`*.g.dart`, `*.freezed.dart`) **não são versionados** — rode `gen` depois de
clonar ou de mexer em `@riverpod`/`@freezed`.

`--no-select` é obrigatório em execução não-interativa.

## Escada de verificação

Verifique sempre no degrau mais barato que responda à pergunta.

| Degrau | O quê | Comando | Custo | Quem avalia |
|---|---|---|---|---|
| 0 | mockup antes do código | agente renderiza HTML | segundos | usuário |
| 1 | análise do arquivo editado | automático (hook `PostToolUse`) | ~2 s | **agente** |
| 2 | teste do escopo tocado | `fvm flutter test <caminho>` | ~5 s | **agente** |
| 3 | app de pé com hot reload | `.claude/launch.json` (`-d macos`) | ~1 s por edit | usuário |
| 4 | gate completo | ver "Definição de pronto" | minutos | CI |

Só suba de degrau quando o de baixo não responder. **O degrau 4 roda antes do
PR, nunca durante.**

⚠️ **Falta o degrau de UI que o agente avalia sozinho** — golden test. As fontes
Inter e IBM Plex Mono não estão empacotadas, então golden renderiza caixinha.
Enquanto isso não existir, toda iteração de layout depende do usuário olhar a
tela. É a fatia `andaime-de-golden` em [`docs/state.md`](docs/state.md).

Para trabalho de layout prefira `-d macos`: hot reload igual, ciclo mais curto
que o simulador. Simulador só quando o comportamento é específico de iOS.

## Arquitetura

**Camadas com fluxo unidirecional: `presentation → domain ← data`.**

- `domain/` — entidades imutáveis (freezed), interfaces de repository, use cases
  só quando houver regra de negócio real. **Nunca** importa Flutter, PowerSync
  ou Supabase.
- `data/` — implementa as interfaces do domínio; mapeia linhas ↔ entidades na
  fronteira.
- `presentation/` — providers/notifiers Riverpod.

Regras que não se negociam:

- **Persistência** é SQL bruto do PowerSync (`watch`/`execute`) atrás de
  repositories que dependem de `SqliteConnection` (mockável). Sem Drift
  ([ADR 0002](docs/adr/0002-persistencia-raw-sql-vs-drift.md)).
- **Erros** viram `Result<T, Failure>` (de `package:core`) na camada `data`.
  Exception do SDK **nunca** vaza para a UI.
- **Estado/DI**: Riverpod 3 com code generation. Instâncias abertas em
  `bootstrap` são injetadas via `overrideWithValue`.
- **Imutabilidade**: `final`/`const` por padrão, `copyWith` para mudar.
- **Logs**: `AppLogger` (redige segredos). Nunca `print`.

## Onde colocar código

```
apps/finance/lib/
  bootstrap.dart · app.dart · main_<flavor>.dart   # composição (não testados em unidade)
  di/providers.dart                                 # composition root
  router/                                           # go_router + guard de auth
  features/<feature>/{domain,data,presentation}/
packages/core/          # Dart puro: Result/Failure, logger, AppEnv, extensions
packages/database/      # schema PowerSync, SupabaseConnector, PowerSyncService
packages/design_system/ # tema, tokens, widgets base
supabase/migrations/    # SQL versionado (schema + RLS + publication)
supabase/functions/     # Edge Functions (pipeline de Open Finance)
powersync/sync_rules.yaml
```

| O que | Onde |
|---|---|
| Utilitário transversal (Dart puro, sem Flutter) | `packages/core` |
| Persistência / sincronização | `packages/database` |
| Tema / widgets base reutilizáveis | `packages/design_system` |
| Nova feature | `apps/finance/lib/features/<feature>/` |

Feature nasce dentro do app e só é **promovida a `packages/`** quando estabiliza.

## Backend — Supabase e PowerSync

- Supabase local roda nas portas **553xx** (offset +1000) para coexistir com o
  stack `finance-dashboard`. **Nunca** derrube o `finance-dashboard`.
- Toda tabela nova: PK `id`, `owner_id`, timestamps, **RLS obrigatória**,
  trigger de `updated_at`. Some ao schema local em
  `packages/database/lib/src/schema.dart` (a coluna `id` é implícita).
- **Função de apoio de RLS nasce no schema `private`**, nunca em `public` — o
  PostgREST expõe `public`, e `SECURITY DEFINER` ali fica chamável por `anon`.
  Use `private.is_space_member` / `has_space_role` / `is_space_owner`. Função de
  trigger pode ficar em `public`, com `revoke execute … from anon, authenticated,
  public` e `set search_path = ''`.
- **Schema muda só por arquivo em `supabase/migrations/` aplicado com
  `supabase db push`.** O `apply_migration` do MCP grava histórico que o repo não
  reproduz. Rode `get_advisors` depois de mudar schema.
- A publication `powersync` é `FOR ALL TABLES`; garanta `REPLICA IDENTITY FULL`.
- **Republicar `sync_rules.yaml` é passo manual no dashboard.** Regra velha se
  manifesta como tela vazia, sem erro.

Antes de mexer em algo sensível, leia o cabeçalho do arquivo — a medição que
justifica a regra está lá, não neste documento:

| Antes de mexer em | Leia |
|---|---|
| direção de lançamento importado | `supabase/functions/_shared/ingest.ts` |
| worker de sincronização | `supabase/functions/pluggy-sync-worker/index.ts` |
| policy ou papel de membro | `supabase/migrations/20260728210321_papeis_de_membro.sql` |
| INSERT que some sem erro | `supabase/migrations/20260728204229_espaco_novo_visivel_a_si_mesmo.sql` |
| convenção de `amount_minor` e cor de categoria | `supabase/migrations/20260727151151_transactions_categories_budgets.sql` |
| qualquer UI | `packages/design_system/lib/src/theme/app_tokens.dart` |
| UI de progresso | `packages/design_system/lib/src/widgets/savings_progress.dart` |

## Ciclo da fatia

```bash
tool/new-slice.sh <nome> [feat|fix|chore|docs|test|perf]   # contrato + branch
#   contrato → execução → aprovação → gate → PR
tool/close-slice.sh                                         # fecha e limpa
```

1. **Contrato** — `docs/slices/<nome>.md`, sem código. Se tem UI, o mockup é
   aprovado **aqui** e mora em `docs/slices/<nome>.mockup.html`, não na conversa.
   Commite contrato + mockup como **primeiro commit do branch**.
2. **Execução** — domain → teste → data → presentation, commit a cada camada que
   fecha com teste verde. Abra o PR como **draft** se quiser CI durante o
   trabalho.
3. **Aprovação** — usuário, uma rodada, só quando já está perto do mockup.
4. **Fechamento** — `tool/close-slice.sh`, reescreva `docs/state.md`, ADR se
   houve decisão cara, `docs/surfaces.md` se nasceu tela.
5. **Portão** — gate completo, push, `gh pr ready`.
6. **Merge** — decisão do usuário, nunca automática.

**A ordem 4 antes de 5 é obrigatória**: o guarda de fatia fechada derruba PR
pronto com contrato aberto.

Uma fatia = uma sessão. Se o "pronto quando" precisa da palavra **"e"**, são
duas fatias. Referência de tamanho: 800–1.800 linhas, até ~20 arquivos, no
máximo 1 superfície nova.

**Retomar fatia no meio** — o estado está no repo, não na sessão:

```bash
git diff --stat $(git merge-base HEAD origin/main)..HEAD
git log --oneline $(git merge-base HEAD origin/main)..HEAD
```

## Definição de pronto

```bash
fvm dart run melos run gen --no-select        # 1. code generation
fvm dart format .                             # 2. formatação
fvm dart run melos run analyze --no-select    # 3. análise (zero infos/warnings)
fvm dart run melos run coverage --no-select   # 4. testes + cobertura
bash tool/check_coverage.sh 80                # 5. gate >= 80%
bash tool/guards.sh                           # 6. guardas de documento
```

`analyze` roda com `--fatal-infos --fatal-warnings` (`very_good_analysis`):
**zero** issues.

Cobertura: meta 80% na lógica de negócio (domain + data + state). Glue de
composição (`bootstrap`, entrypoints, `di/providers.dart`,
`powersync_service.dart`, gerados) é excluída da métrica — cubra por teste de
integração. Prefira **fakes**/mocktail; mocke `SqliteConnection`, não
`PowerSyncDatabase` (que é `base`).

## Git

**Nunca** commite na `main`. Branch por fatia a partir de **`origin/main`** (a
`main` local costuma estar atrás), Conventional Commits no imperativo, PR com CI
verde antes do merge.

```bash
git rev-list --left-right --count HEAD...origin/main   # o segundo número tem que ser 0
```

## Segredos

Config por flavor via `--dart-define-from-file=env/<flavor>.json`, com
`env/*.json` git-ignored (exceto `example.json`). No cliente, apenas a
**publishable key** — nunca a service-role. `AppEnv` valida no boot.
