# Roadmap e estado do projeto

Documento vivo. O **PRD** define *o quê* e *por quê*; este arquivo registra
*onde estamos*. Atualize junto com o PR que muda o estado.

- Última atualização: **2026-07-27**
- Branch de trabalho atual: `feat/transacoes`
- `main` em `0213d3c` (design system mesclado via PR #10)

---

## Estado em uma frase

A **fundação está madura e validada**; o **produto quase não existe**. Auth,
multi-tenancy por espaços, política de dinheiro, sincronização offline-first e o
design system completo estão de pé. Nenhuma transação pode ser registrada ainda.

---

## Fase 0 — Fundação (MVP mínimo viável)

> Objetivo do PRD: validar o loop de registro individual, com "primeiro gasto em
> ≤ 30 segundos".

### Concluído

| Item | Onde |
|---|---|
| Monorepo Melos + Pub Workspaces + FVM pinado | raiz, `.fvmrc` |
| CI: format · analyze (`--fatal-infos`) · testes · gate de cobertura 80% · build smoke web | `.github/workflows/ci.yaml` |
| `Result<T, Failure>` e `AppLogger` (redige segredos) | `packages/core` |
| `Money` — inteiro em unidades mínimas, `allocate()` por maior resto | `packages/core/lib/src/money/money.dart` |
| `AppEnv` com falha rápida no boot | `packages/core/lib/src/env/app_env.dart` |
| Auth: login, cadastro, guard de rota, ciclo de vida do sync | `apps/finance/lib/features/auth`, `features/sync` |
| Espaços: entidade, repository, providers, espaço pessoal criado no signup | `apps/finance/lib/features/spaces` |
| Multi-tenancy: RLS por membership com `SECURITY DEFINER` | `supabase/migrations/20260717120000_spaces_and_membership.sql` |
| Sync rules espelhando o RLS (buckets por usuário e por espaço) | `powersync/sync_rules.yaml` |
| PowerSync: schema local, connector, serviço | `packages/database` |
| **Design system completo**: tema claro/escuro, tokens, 10 widgets, 118 testes | `packages/design_system` |
| 6 ADRs (stack, persistência, camadas, multi-tenancy, Pluggy, dinheiro) | `docs/adr/` |

### Pendente — é isto que fecha a Fase 0

- [ ] **Migration `categories`** — com seed das categorias de sistema
      (`is_system = true`), `space_id` nulo para as globais, RLS, `parent_category_id`.
- [ ] **Migration `transactions`** — `amount_minor bigint`, `space_id`,
      `account_id`, `created_by`, `type`, `category_id`, `occurred_at`, `source`,
      `is_shared`, `recurrence_id`; RLS por membership; `replica identity full`.
- [ ] **Migration `budgets`** — por categoria e período (mensal/semanal).
- [ ] Adicionar as três tabelas ao **schema PowerSync** e às **sync rules**
      (`by_space.data`).
- [ ] Domain + data + providers de `transactions` e `categories`.
- [ ] **Shell de navegação** com `AppBottomNav` (Início · Espaços · + · Social ·
      Perfil), com Social e Perfil como placeholders honestos.
- [ ] **Tela de registro rápido** — teclado numérico próprio, campos
      pré-preenchidos, caminho mínimo de 3 toques.
- [ ] **Lista de transações** — seções por dia com total, estado de
      "aguardando envio".
- [ ] **Home do espaço** — saldo do mês como momento alto, tiras de orçamento,
      atividade recente.
- [ ] **Orçamento mensal básico** — cálculo de acumulado vs. limite e alertas em
      80% / 100% (RN-1.3).
- [ ] **Onboarding minimalista** — 3 telas de pilar + primeira ação.

---

## Fases 1 a 4 — não iniciadas

Nada de código. O que existe é **desenho**, não implementação.

| Fase | Escopo (PRD §14) | Estado |
|---|---|---|
| **1 — Poupança + Open Finance** | Open Finance limitado no grátis, metas de poupança (4 tipos), detecção/confirmação de contribuição, streaks, badges, categorização por IA | Pipeline Pluggy **inteiramente desenhado** em [ADR 0005](adr/0005-open-finance-pluggy-server-side.md) — zero linhas escritas. Nenhuma Edge Function existe. |
| **2 — Colaboração** | Espaços `group` (split, saldos, liquidação Pix) e `household` (transparência total, contas vinculadas), convites, matriz de papéis | Schema de espaços e papéis **já pronto**. `Money.allocate()` já resolve a matemática do split (RN-2.1). Falta tudo de UI, `expense_splits`, `settlements`. |
| **3 — Social + gamificação** | `friendships`, feed, reações, desafios com ranking, push | Nada. |
| **4 — Monetização + escala** | Paywall premium, relatórios com IA, widget | Nada. `profiles` não tem `subscription_tier`. |

---

## Débitos técnicos conhecidos

Ordenados por risco. Todos verificados no código.

### Alto — corrigir na fatia de transações

- [ ] **`accounts` sem filtro de espaço.**
      [`accounts_repository_impl.dart:32`](../apps/finance/lib/features/accounts/data/accounts_repository_impl.dart)
      faz `SELECT * FROM accounts` sem cláusula alguma, contrariando o
      [ADR 0004](adr/0004-multi-tenancy-por-espacos.md) ("queries precisam filtrar
      por `space_id` do espaço ativo"). Inofensivo hoje porque só existe um
      usuário; no minuto que um household vincular contas, a lista mistura contas
      de outros donos. **Corrigir antes de o padrão ser copiado para
      `transactions`.**

### Médio

- [ ] **Entidade `Account` incompleta.** Tem 6 campos; o PRD §5.2 pede
      `account_type`, `institution`, `current_balance_minor`, `is_savings_target`,
      `linked_space_id`. A coluna `linked_space_id` **já existe** na migration e no
      schema PowerSync, mas não na entidade nem no repository — implementação pela
      metade.
- [ ] **`profiles` sem `username`.** O PRD pede `username` **unique** (handle
      público do grafo social), `pix_key`, `avatar_url`, `phone`,
      `subscription_tier`. Nada é Fase 0, mas `username unique` é o campo mais
      caro de adicionar depois (backfill + escolha de handle para contas
      existentes). Vale decidir se entra no cadastro desde já.
- [ ] **Sem testes de integração.** `apps/finance/integration_test/` tem só um
      README. O CLAUDE.md §7 excluí a glue de sync/composição da métrica de
      cobertura justamente esperando que ela seja coberta por integração.
- [ ] **Golden tests ausentes.** Depende de empacotar as fontes primeiro (abaixo).

### Baixo

- [ ] **Fontes não empacotadas.** Inter e IBM Plex Mono estão declaradas em
      `AppTypography`, mas os binários não estão no repo — o Flutter cai na fonte
      da plataforma. `tabularFigures` funciona de qualquer forma (SF e Roboto
      suportam `tnum`). Empacotar destrava os goldens.
- [ ] **Contraste não medido.** Mirado em WCAG AA (e `textMuted` foi movido de
      `ink-500` para `ink-600` por isso), mas sem verificação automática. Checar
      `textMuted` sobre `surfaceSunken` e o âmbar no tema escuro.
- [ ] **Set de ícones não escolhido.** Hoje Material Icons. Decidir antes de as
      telas multiplicarem os pontos de uso.

---

## Ambiente de desenvolvimento

| Item | Estado |
|---|---|
| macOS desktop | ✅ Roda. Entitlement `network.client` corrigida no PR #10. |
| iOS Simulator | ✅ Xcode 26.1.1, simuladores disponíveis. `127.0.0.1` alcança o host. |
| Supabase local | ✅ Configurado nas portas 553xx (offset +1000, coexiste com `finance-dashboard`). Exige Docker de pé. |
| **PowerSync** | ⚠️ `POWERSYNC_URL` em `env/dev.json` é **placeholder** (`REPLACE-WITH-YOUR-POWERSYNC-INSTANCE`). O app boota (o `AppEnv` valida presença, não formato), mas o sync falha ao conectar. Precisa de uma instância (Cloud free tier ou self-hosted) apontada para o Postgres local, com as sync rules publicadas. |
| Web (Chrome) | ⚠️ Compila, mas falta `sqlite3.wasm` + worker em `apps/finance/web/`. `PowerSyncService.open()` falharia. |
| Android | ⚠️ Três bloqueios: `cmdline-tools` ausente, nenhum AVD criado, e o `env/dev.json` não serve (no emulador o host é `10.0.2.2`, não `127.0.0.1`, e o Android 9+ bloqueia cleartext — o `AndroidManifest.xml` não tem exceção). Precisaria de `env/dev-android.json` + network security config. |

---

## Questões abertas do PRD (§15)

| # | Questão | Status |
|---|---|---|
| 1 | Regime de renda para metas percentuais | Aberta — decidir na Fase 1 |
| 2 | Algoritmo de simplificação de dívidas | Aberta. `Money.allocate()` já resolve o **split** de uma despesa (RN-2.1); a minimização de transferências entre membros (RN-2.2) é problema distinto e segue em aberto |
| 3 | Provedor de Open Finance | ✅ **Respondida** — Pluggy, server-side ([ADR 0005](adr/0005-open-finance-pluggy-server-side.md)). O PRD está desatualizado neste ponto |
| 4 | IA de categorização: modelo próprio vs. API | Aberta |
| 5 | Detecção de poupança — falsos positivos | Aberta |
| 6 | Limite do Open Finance no grátis (1 ou 2 contas) | Aberta — depende de dados de conversão |
| 7 | Household com 3+ pessoas | Aberta. O schema **já suporta** (`space_members`); é decisão de UX |
| 8 | Moderação de feed/comentários | Aberta — Fase 3 |
| 9 | Cadência de notificações | Aberta — Fase 3 |
| 10 | Gamificação vs. saúde financeira | Aberta — princípio de produto, revisitar na Fase 1 |

---

## Referências

- [`CLAUDE.md`](../CLAUDE.md) — como trabalhar no repo (toolchain, comandos,
  Definição de Pronto, fluxo git)
- [`docs/adr/`](adr) — decisões de arquitetura e seus porquês
- [`docs/pluggy-api-reference.md`](pluggy-api-reference.md) — referência da API do
  agregador
- Design system visual: projeto `Finance App — Design System` no Claude Design.
  Os previews são HTML; o que sincroniza com o Dart é a **especificação**, não o
  código
