# Roadmap e estado do projeto

Documento vivo. O **PRD** define *o quê* e *por quê*; este arquivo registra
*onde estamos*. Atualize junto com o PR que muda o estado.

- Última atualização: **2026-07-27**
- Branch de trabalho atual: `feat/transacao-edicao`

---

## Estado em uma frase

**O loop central da Fase 0 fecha.** Dá para registrar um gasto em três toques,
ver a lista do mês agrupada por dia, definir e ajustar limite de orçamento com
alerta em 80% e 100%, e trocar de espaço. Faltam duas telas acessórias (abaixo)
e o onboarding.

## Por onde começar numa sessão nova

1. Leia [`CLAUDE.md`](../CLAUDE.md) — toolchain (sempre `fvm`), comandos Melos e
   a Definição de Pronto.
2. Leia este arquivo até o fim: o que está pronto, o que falta, e os débitos.
3. Antes de mexer em schema, leia o **cabeçalho** da migration
   `20260727151151_transactions_categories_budgets.sql`. Ele documenta as duas
   convenções que mais confundem: `amount_minor` positivo com direção em `type`,
   e cor de categoria como índice de paleta em vez de hex.
4. Antes de mexer em UI, leia a doc de `AppTokens` em
   `packages/design_system/lib/src/theme/app_tokens.dart` — a regra "despesa é o
   estado neutro" é a espinha do sistema visual.
5. Para rodar: `supabase start` (precisa de Docker) e depois
   `cd apps/finance && fvm flutter run -d iphone --target lib/main_dev.dart --dart-define-from-file=../../env/dev.json`.
   Criar conta é passo manual.

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

### Concluído na fatia de transações (branch `feat/transacoes`)

| Item | Onde |
|---|---|
| Migrations `categories` + `transactions` + `budgets`, com RLS por membership, `replica identity full` e seed de 10 categorias de sistema | `supabase/migrations/20260727151151_*.sql` |
| Schema PowerSync e sync rules das três tabelas (+ bucket `global` para as categorias de sistema) | `packages/database/lib/src/schema.dart`, `powersync/sync_rules.yaml` |
| Domain: `Transaction`, `Category`, `Budget`, `BudgetUsage`, `MonthSummary` | `apps/finance/lib/features/{transactions,categories,budgets}/domain` |
| Data: os três repositories sobre SQL bruto | `.../data` |
| Providers: mês em foco, transações do mês, resumo, categorias indexadas, uso de orçamento | `.../presentation` |
| **Escopo de espaço em `accounts` corrigido** (débito de risco alto) | `apps/finance/lib/features/accounts` |
| Shell de navegação com as 4 abas + ação central | `apps/finance/lib/features/shell` |
| Registro rápido: teclado numérico próprio, 3 toques até salvar | `.../transactions/presentation/quick_entry_*` |
| Lista de transações agrupada por dia, com total do dia | `.../transactions/presentation/transaction_list.dart`, `transactions_page.dart` |
| Home do espaço: saldo como momento alto, orçamento, atividade recente | `.../home/presentation/space_home_page.dart` |
| Página de espaços com troca de contexto | `.../spaces/presentation/spaces_page.dart` |
| Orçamento: acumulado vs. limite com limiares de 80% / 100% (RN-1.3) | `BudgetUsage` + `BudgetProgress` |

### Concluído na fatia de orçamento (branch `feat/orcamento-ui`)

| Item | Onde |
|---|---|
| **Escrita de orçamento consertada** (era quebrada, ver débitos resolvidos) | `budgets_repository_impl.dart` |
| Página de orçamentos do mês, com quanto ainda cabe por categoria | `.../budgets/presentation/budgets_page.dart` |
| Folha de criar/editar/remover limite, com vigência explícita | `.../budgets/presentation/budget_form_sheet.dart` |
| Controller do formulário (orçamento a editar como argumento do provider) | `.../budgets/presentation/budget_form_controller.dart` |
| Entrada pela home: ação "Gerenciar" e convite para quem já registra | `.../home/presentation/space_home_page.dart` |
| `AmountDisplay`, `AmountKeypad` e `SheetGrabHandle` promovidos | `packages/design_system` |
| `MinorDigits` (acumulador de centavos) e `monthLabel` promovidos | `packages/core` |
| `CategoryPicker` compartilhado entre registro rápido e orçamento | `.../categories/presentation/category_picker.dart` |

**Modelo de vigência.** Salvar grava `starts_at` no mês em foco: mudar o limite
em julho cria uma linha nova a partir de julho e deixa junho como estava, então
"quanto eu tinha orçado" continua honesto mês a mês. Salvar duas vezes no mesmo
mês substitui o limite, sem duplicar. O `budgetUsageProvider` reduz a um
orçamento por categoria — o mais recente vigente no mês.

### Concluído na fatia de edição de lançamento (branch `feat/transacao-edicao`)

| Item | Onde |
|---|---|
| Folha de detalhe/edição, com excluir sob confirmação | `.../transactions/presentation/transaction_edit_sheet.dart` |
| Controller da edição (lançamento como argumento do provider) | `.../transactions/presentation/transaction_edit_controller.dart` |
| Toque na linha abre a edição, na lista do mês e na atividade recente | `transactions_page.dart`, `space_home_page.dart` |
| `pumpScreen` aceita repositórios que registram escrita | `test/helpers/app_harness.dart` |

Três decisões que valem lembrar:

- **`savings` e `transfer` aparecem como tipo fixo**, não como segmento. Um
  segmento de duas posições trocaria o tipo em silêncio no primeiro toque.
- **Categoria é opcional na edição**, ao contrário do registro rápido:
  lançamento importado do Open Finance chega sem categoria, e exigir uma
  impediria corrigir o valor de algo que ainda não se sabe classificar.
- **Ações em rodapé fixo**, campos rolando acima: seis campos e um teclado não
  cabem numa tela pequena.

### Pendente — é isto que fecha a Fase 0

- [ ] **Onboarding minimalista** — 3 telas de pilar + primeira ação (PRD §10.2).
- [ ] **Criar categoria de usuário.** Repositório pronto; sem UI. Hoje o
      formulário de orçamento diz "todas as categorias já têm limite neste mês"
      quando acabam as categorias — o caminho para criar uma nova sai daqui.

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

### Resolvido

- [x] **`upsert` de orçamento nunca funcionou.** Usava `ON CONFLICT` espelhando
      a unique do Postgres, mas as tabelas locais do PowerSync são **views com
      triggers `INSTEAD OF`** e o SQLite recusa: `cannot UPSERT a view`. Toda
      tentativa de salvar limite pelo app falharia — e o teste existente passava
      porque mocka a conexão e só inspeciona o texto do SQL. Virou
      select-then-write, com as statements em constantes e um teste de guarda que
      as roda contra uma view com os mesmos triggers. **Lição transferível:**
      qualquer SQL novo sobre tabela do PowerSync precisa de um teste que execute
      de verdade; mock de `SqliteConnection` não distingue SQL válido de SQL que
      o SQLite recusa.
- [x] **Vigência de orçamento vazava entre meses.** `budgetUsageProvider`
      comparava `DateTime` cru, então um limite que começa em 1º de julho em UTC
      entrava em junho no fuso de Brasília; e incluía toda linha histórica, o que
      duplicaria a categoria na lista assim que houvesse reorçamento. Agora
      compara mês a mês e reduz a um orçamento por categoria.
- [x] **`accounts` sem filtro de espaço** — corrigido na fatia de transações.
      `watchAll()` virou `watchOwned()` (filtra por `owner_id`) mais
      `watchForSpace()` (dono **ou** conta vinculada ao household), com teste
      verificando o SQL gerado. Era o débito de risco alto: contrariava o
      [ADR 0004](adr/0004-multi-tenancy-por-espacos.md) e viraria vazamento
      entre membros assim que um household vinculasse contas.

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
- [ ] **As telas nunca foram vistas renderizadas com fonte real.** A verificação
      até agora é por teste de widget (alturas, ausência de overflow nos dois
      temas). Para olhar de fato é preciso uma sessão autenticada, e criar conta
      não é algo que o agente faça — é passo manual.
- [ ] **Abas sem URL própria.** O `AppShell` usa `IndexedStack`, então deep link
      por aba não funciona. Quando virar requisito, trocar por
      `StatefulShellRoute` do go_router.
- [ ] **Duplicação de fakes nos testes.** `test/helpers/app_harness.dart`
      centraliza os fakes, mas quatro arquivos de teste anteriores ainda têm a
      sua própria cópia. Vale migrá-los. O harness já aceita repositório
      injetado, então o caminho está aberto.
- [ ] **Editar lançamento não mexe em conta nem em rateio.** `account_id` e
      `is_shared` são preservados, mas não editáveis — conta pertence à entidade
      `Account` incompleta (acima) e rateio é Fase 2.
- [ ] **Orçamento semanal existe no schema, não na UI.** `BudgetPeriod.weekly`
      persiste, mas `budgetUsageProvider` filtra só mensal e a folha grava sempre
      mensal. Um limite semanal criado por SQL fica invisível no app.
- [ ] **Remover orçamento apaga a linha, não a vigência.** Se houver limite de
      junho e de julho para a mesma categoria, remover o de julho faz o de junho
      voltar a valer (é o mais recente vigente). Coerente com o modelo, mas pode
      surpreender; quando incomodar, o caminho é uma linha de "sem limite" em vez
      de `DELETE`.

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
