# Roadmap e estado do projeto

Documento vivo. O **PRD** define *o quê* e *por quê*; este arquivo registra
*onde estamos*. Atualize junto com o PR que muda o estado.

- Última atualização: **2026-07-27**
- Branch de trabalho atual: `feat/metas-poupanca`

---

## Estado em uma frase

**A Fase 1 começou pelo Pilar 3: metas de poupança existem.** A Fase 0 está
fechada (apresentação, gasto em três toques, edição, orçamento com alerta em 80%
e 100%, categoria própria, troca de espaço, contas completas), o lançamento sabe
de que conta saiu, e a camada local tem 27 testes de integração rodando no CI
contra um PowerSync de verdade.

Agora dá para **criar meta por objetivo, valor fixo mensal ou percentual da
renda, guardar valor e ver progresso** numa aba própria (Poupança, no lugar do
placeholder Social). A detecção automática de contribuição fica pendente do Open
Finance — o resto da Fase 1 é Open Finance (infra nova, credenciais Pluggy),
streaks/badges e categorização por IA.

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
   estado neutro" é a espinha do sistema visual. Se a UI mostra **progresso**,
   leia também a doc de `SavingsProgress`: barra de meta e barra de orçamento
   têm a mesma forma e significados opostos, e o que as separa está lá.
5. Antes de criar coluna que guarde um total, leia
   [ADR 0007](adr/0007-agregado-derivado-vs-coluna.md). Agregado neste app é
   derivado; coluna é só para fato informado.
6. Para rodar: **não precisa de Docker.** O `env/dev.json` aponta para um
   Supabase e um PowerSync **na nuvem** (o `supabase start` local existe para
   testar migrations, não para rodar o app).
   `cd apps/finance && fvm flutter run -d iphone --target lib/main_dev.dart --dart-define-from-file=../../env/dev.json`.
   Criar conta é passo manual.
7. **Se as telas ficarem vazias ou o registro rápido travar em "nenhuma
   categoria", suspeite das sync rules publicadas.** O arquivo
   `powersync/sync_rules.yaml` do repo **não é publicado automaticamente**: toda
   vez que ele muda, é preciso colar o conteúdo no editor de Sync Rules do
   dashboard do PowerSync e fazer Deploy. Para diagnosticar, inspecione o SQLite
   local do app (`ps_buckets` mostra quais buckets chegaram) — foi assim que se
   descobriu que faltava o bucket `global`.

---

## Fase 0 — Fundação (MVP mínimo viável)

> Objetivo do PRD: validar o loop de registro individual, com "primeiro gasto em
> ≤ 30 segundos".

### Concluído

| Item | Onde |
|---|---|
| Monorepo Melos + Pub Workspaces + FVM pinado | raiz, `.fvmrc` |
| CI: format · analyze (`--fatal-infos`) · testes · gate de cobertura 80% · **integração sobre PowerSync real** · build smoke web | `.github/workflows/ci.yaml` |
| `Result<T, Failure>` e `AppLogger` (redige segredos) | `packages/core` |
| `Money` — inteiro em unidades mínimas, `allocate()` por maior resto | `packages/core/lib/src/money/money.dart` |
| `AppEnv` com falha rápida no boot | `packages/core/lib/src/env/app_env.dart` |
| Auth: login, cadastro, guard de rota, ciclo de vida do sync | `apps/finance/lib/features/auth`, `features/sync` |
| Espaços: entidade, repository, providers, espaço pessoal criado no signup | `apps/finance/lib/features/spaces` |
| Multi-tenancy: RLS por membership com `SECURITY DEFINER` | `supabase/migrations/20260717120000_spaces_and_membership.sql` |
| Sync rules espelhando o RLS (buckets por usuário e por espaço) | `powersync/sync_rules.yaml` |
| PowerSync: schema local, connector, serviço | `packages/database` |
| **Design system completo**: tema claro/escuro, tokens, 10 widgets, 118 testes | `packages/design_system` |
| 7 ADRs (stack, persistência, camadas, multi-tenancy, Pluggy, dinheiro, agregados) | `docs/adr/` |

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

### Concluído na fatia de categoria (branch `feat/categoria-usuario`)

| Item | Onde |
|---|---|
| Folha de criar categoria: nome, ícone, matiz, com prévia | `.../categories/presentation/category_form_sheet.dart` |
| Controller da criação | `.../categories/presentation/category_form_controller.dart` |
| `colorIndex` passa a ser **renderizado** (`colorsAt` + `CategorySwatch.colorIndex`) | `packages/design_system` |
| Chip "Nova" fora da rolagem, e estado vazio com saída | `.../categories/presentation/category_picker.dart` |
| Fim da duplicação "Alimentação / Alimentação" na lista | `.../transactions/presentation/transaction_list.dart` |

**As telas foram vistas renderizadas** (iPhone 17 Pro, simulador, contra Supabase
e PowerSync reais). Foi essa passagem que revelou a duplicação na lista e o chip
"Nova" exigindo seis arrastes — nenhum dos dois aparecia em teste de widget.

### Concluído na fatia de onboarding (branch `feat/onboarding`)

| Item | Onde |
|---|---|
| Três telas de pilar, progresso em barras, "Pular" sempre visível | `.../onboarding/presentation/onboarding_page.dart` |
| Fragmentos: o do pilar 1 é a `TransactionTile` de verdade | `.../onboarding/presentation/onboarding_pillars.dart` |
| Entrega dentro da ação: abre o registro rápido com orientação de primeira vez | `quick_entry_sheet.dart` (`showFirstRunHint`) |
| Preferência local sem dependência nova: tabela `localOnly` `app_prefs` | `packages/database/lib/src/schema.dart`, `.../onboarding/data/onboarding_store.dart` |
| Guard de primeira execução no router (autenticar → apresentar → home) | `apps/finance/lib/router/app_router.dart` |

Desenhado na rodada 2 do Claude Design e aprovado antes de virar Dart. As duas
decisões que não se leem no código:

- **O produto se apresenta com o próprio produto** — fragmento real da interface
  em vez de ilustração. A regra de dinheiro do sistema (receita com `+` e cor,
  despesa sem cor) é demonstrada nos primeiros dez segundos.
- **Pilares 2 e 3 dizem que ainda não existem.** Chip de contorno em texto
  apagado, nunca âmbar. Os fragmentos deles são esboço, não especificação das
  telas das fases 1 e 2.

### Fase 0 — completa

Não há mais itens pendentes da Fase 0.

---

## Preparo para a Fase 1

### Concluído na fatia de contas (branch `feat/contas`)

| Item | Onde |
|---|---|
| Migration com `account_type`, `institution`, `current_balance_minor`, `is_savings_target` (+ índice parcial de alvo de poupança) | `supabase/migrations/20260727210000_accounts_profile.sql` |
| `AccountType` mapeando os subtipos da Pluggy sem caixa "não sei" | `.../accounts/domain/account.dart` |
| `Account` completa, com `signedBalance` e tolerância a linha anterior à migration | idem |
| Repository com `create`/`update`/`delete`, statements em `AccountSql` e **teste que roda o SQL contra uma view com triggers `INSTEAD OF`** | `.../accounts/data/accounts_repository_impl.dart` |
| Aba Perfil de verdade, no lugar do placeholder: contas, total líquido e a promessa das fases seguintes | `.../profile/presentation/profile_page.dart` |
| Folha de criar/editar/excluir conta, com o mesmo teclado do registro rápido | `.../accounts/presentation/account_form_sheet.dart` |
| `linkableSpaces` e `accountsNetBalance` | `.../accounts/presentation/accounts_providers.dart` |
| `FakeAccountsRepository` e `testAccount` no harness de teste | `test/helpers/app_harness.dart` |

Três decisões que não se leem no código:

- **Saldo é snapshot, não soma de lançamento.** O usuário informa quanto tem
  hoje. Derivar de `transactions` daria um número errado com cara de certo,
  porque lançamento manual cobre uma fração do extrato. Na Fase 1 a ingestão da
  Pluggy passa a ser dona dessa coluna nas contas de Open Finance (ADR 0005).
- **`current_balance_minor` é positivo e a direção vem de `account_type`** —
  mesma convenção de `amount_minor`. Em cartão o número é a **fatura**, que é
  também como a Pluggy entrega. O sinal aparece só no domínio, em
  `Account.signedBalance`.
- **Vínculo a household não aparece na Fase 0.** `linkableSpaces` filtra
  `household`, que ainda não existe, então o campo simplesmente não é
  renderizado — em vez de oferecer uma escolha de um item só.

**As telas foram vistas renderizadas** (iPhone 17 Pro, contra Supabase e
PowerSync reais): criar → aparecer na lista → editar → excluir, com a linha indo
e sumindo do Postgres. Foi essa passagem que pegou o cartão sendo pintado de
vermelho — `MoneyTone.over` é reservado a orçamento estourado, e usar vermelho
para dívida ordinária é exatamente o "vermelho lê como erro" que o design system
existe para evitar. Hoje o tom é neutro, com um teste de guarda.

### Concluído na fatia da conta no lançamento (branch `feat/conta-no-lancamento`)

| Item | Onde |
|---|---|
| `AccountPicker`, espelhando o gesto do `CategoryPicker` | `.../accounts/presentation/account_picker.dart` |
| Conta no registro rápido e na folha de edição | `quick_entry_sheet.dart`, `transaction_edit_sheet.dart` |
| `soleAccountIdProvider` — padrão de conta única, sem custar toque | `.../accounts/presentation/accounts_providers.dart` |
| `accountLabelsProvider` — nome da conta na lista **só quando há mais de uma** | idem |
| Migration `balance_as_of` e a data do saldo na tela | `supabase/migrations/20260727230000_*.sql`, `account_tile.dart` |
| `formatDayLabel` promovido para `package:core` | `packages/core/lib/src/format/day_label.dart` |

Três decisões que não se leem no código:

- **Com uma conta só, ela já vem escolhida.** Perguntar custaria um toque para
  uma resposta que já se sabe, e o registro rápido tem um orçamento de três.
  Com duas ou mais não há palpite honesto, e o campo fica vazio. A regra vive
  num provider porque a tela e o controller precisam da **mesma** resposta: o
  chip marcado tem de ser a conta que o Salvar grava.
- **`accountTouched` distingue "ainda não escolhi" de "tirei de propósito".**
  Sem essa marca, desmarcar a conta única seria desfeito pelo padrão no Salvar.
- **A edição não atribui conta sozinha.** O lançamento já existe; dar conta a
  ele por padrão seria inventar dado que ninguém informou.

**Saldo continua snapshot** — registrar gasto não o move. A mitigação é
`balance_as_of`: a tela diz "de hoje", "de ontem", "de 5 de março". A coluna só
se move quando o **valor** muda; renomear a conta não faz o saldo ficar mais
novo, e `updated_at` faria.

**Visto rodando:** conta única já marcada no registro rápido, lançamento
chegando ao Postgres com `account_id`, e o nome da conta aparecendo na linha
assim que existiu uma segunda conta. A passagem pegou "de Hoje" com maiúscula no
meio da frase.

### Concluído na fatia de integração (branch `test/integracao`)

| Item | Onde |
|---|---|
| 18 testes sobre um `PowerSyncDatabase` real, aberto do `appSchema` em diretório temporário | `apps/finance/test_integration/local_persistence_test.dart` |
| `LocalStack`: banco real + container do Riverpod com os repositories de verdade | `.../test_integration/helpers/local_stack.dart` |
| Script `melos run integration` e job próprio no CI | `pubspec.yaml`, `.github/workflows/ci.yaml` |
| README reescrito: o que cobrem, o que não cobrem, e por que o diretório não se chama `integration_test` | `.../test_integration/README.md` |

**Rodam na máquina, sem device e sem rede.** O SDK do PowerSync traz a extensão
nativa por plataforma, então a suíte cabe num runner Linux — foi essa descoberta
que fez a fatia caber no CI em vez de virar um passo manual.

**O diretório não se chama `integration_test` de propósito.** Esse nome é
reservado pelo Flutter: exige `package:integration_test` e um device conectado.
No macOS o desktop conta como device e a exigência passa despercebida; foi o CI
de Linux que a revelou. Se um dia houver teste que precise mesmo de device, aí
cabe um `integration_test/` ao lado, com job em runner macOS.

Cobrem o que a métrica de cobertura exclui (`di/providers.dart`,
`powersync_service.dart`) e, principalmente, são o único lugar em que o SQL do
app encontra as **views com triggers `INSTEAD OF`** de verdade. Há um teste que
afirma explicitamente que a view recusa `UPSERT`, para a lição do orçamento não
voltar a ser folclore.

**Fora de escopo, de propósito:** connector, upload e Supabase. Provar a ida ao
Postgres exige rede, credenciais e conta de teste — a suíte ficaria lenta e
intermitente, e o CI passaria a depender de serviço externo. Essa prova segue
manual, no simulador, e cada fatia a registra no PR.

---

## Fase 1 — Poupança + Open Finance (em andamento)

### Concluído na fatia de metas de poupança (branch `feat/metas-poupanca`)

| Item | Onde |
|---|---|
| Migration `savings_goals` + `savings_contributions`, com RLS por membership, check de forma por tipo e trigger que herda o espaço da meta | `supabase/migrations/20260727235500_savings_goals.sql` |
| Schema PowerSync e sync rules das duas tabelas | `packages/database/lib/src/schema.dart`, `powersync/sync_rules.yaml` |
| Domain: `SavingsGoal`, `SavingsContribution`, `GoalProgress` (a regra de progresso) | `apps/finance/lib/features/savings/domain/` |
| Data: repository sobre SQL bruto, statements em `SavingsSql`, exclusão de meta em transação com as contribuições | `.../savings/data/savings_repository_impl.dart` |
| Providers: progresso por meta, contribuições por meta, total guardado, total do mês, pendentes | `.../savings/presentation/savings_providers.dart` |
| Aba **Poupança** no lugar do placeholder Social | `.../shell/presentation/app_shell.dart`, `.../savings/presentation/savings_page.dart` |
| Folha de criar/editar meta em **dois passos** (tipo → campos daquele tipo) | `.../savings/presentation/goal_form_sheet.dart` |
| Detalhe da meta: progresso, projeção em prosa, histórico de contribuições | `.../savings/presentation/goal_detail_page.dart` |
| Folha "Guardei um valor" (caminho manual da RN-3.2) | `.../savings/presentation/contribution_sheet.dart` |
| `SavingsProgress`, `CompletionSeal` e `ScrollEdgeFade` promovidos | `packages/design_system` |
| `isoDate` promovido para `package:core` (`Budget.dateOnly` delega) | `packages/core/lib/src/format/iso_date.dart` |
| `GoalCopy`: as frases das metas num lugar só, para lista e detalhe não discordarem | `.../savings/presentation/goal_copy.dart` |
| 111 testes da fatia + 12 do design system + 12 de integração | `apps/finance/test/features/savings/`, `test_integration/savings_persistence_test.dart` |

**Rodada 3 do design foi aprovada antes de virar Dart** (guideline de progresso +
3 telas no projeto `Finance App — Design System`).

Quatro decisões que não se leem no código:

- **Não existe coluna `current_amount`.** O PRD §5.2 a lista, mas a RN-3.3 a
  define como "a soma das contribuições confirmadas" — uma agregação, não um
  fato. Offline, uma coluna que precisa ser igual a uma soma desincroniza em
  silêncio: dois aparelhos gravam verdades diferentes e o último upload ganha. O
  progresso é derivado, como `BudgetUsage` já faz sobre `transactions`.
- **Barra de meta e barra de orçamento têm significados opostos**, e dois sinais
  as separam: meta **nunca** usa âmbar nem vermelho (atraso é informação, não
  erro — a mesma razão pela qual despesa não é vermelha), e só meta tem **marca
  de ritmo** (um tick mostrando onde o prazo diria que se estaria hoje). Sem
  prazo, sem tick. Trilho de meta é 8px; de orçamento, 5px.
- **A renda da meta percentual é derivada dos lançamentos `income` do mês**, e a
  tela diz de onde o número saiu. É a resposta à questão aberta #1 do PRD, sem
  campo declarado que envelheceria calado. O custo: quem não lança receita não
  tem base — e aí a tela diz isso em vez de mostrar 0%.
- **`savings_contributions.space_id` é denormalizado** porque **sync rule não faz
  join**: um bucket é `where space_id = bucket.space_id`. Um trigger no Postgres
  o mantém igual ao da meta, então o cliente não precisa acertá-lo e não
  consegue mentir nele.

**O quarto tipo de meta do PRD (`recurring_challenge`) ficou fora**, do banco
inclusive: mede hábito em vez de valor acumulado, precisa de outra tela de
progresso e se sobrepõe ao conceito de `challenges` da Fase 3.

**A detecção automática de contribuição (RN-3.2, ramo 1) não existe** — depende
da ingestão da Pluggy. O schema já nasce com `detected_via`/`confirmed`, a UI já
sabe mostrar e confirmar uma linha pendente, e a ingestão só precisará gravar.

### O que falta na Fase 1

| Item | Estado |
|---|---|
| Open Finance (limitado no grátis) | Pipeline Pluggy **inteiramente desenhado** em [ADR 0005](adr/0005-open-finance-pluggy-server-side.md) — zero linhas escritas. Nenhuma Edge Function existe. |
| Detecção/confirmação automática de contribuição | Metade pronta: schema e UI existem; falta quem crie a linha (ingestão Pluggy) |
| Streaks e badges básicos | Nada. Agora há histórico de contribuição para derivá-los |
| Categorização por IA (premium) | Nada |
| `recurring_challenge` como quarto tipo de meta | Fora de escopo por decisão (ver acima) |

---

## Fases 2 a 4 — não iniciadas

Nada de código. O que existe é **desenho**, não implementação.

| Fase | Escopo (PRD §14) | Estado |
|---|---|---|
| **2 — Colaboração** | Espaços `group` (split, saldos, liquidação Pix) e `household` (transparência total, contas vinculadas), convites, matriz de papéis | Schema de espaços e papéis **já pronto**. `Money.allocate()` já resolve a matemática do split (RN-2.1). Falta tudo de UI, `expense_splits`, `settlements`. |
| **3 — Social + gamificação** | `friendships`, feed, reações, desafios com ranking, push | Nada. |
| **4 — Monetização + escala** | Paywall premium, relatórios com IA, widget | Nada. `profiles` não tem `subscription_tier`. |

---

## Débitos técnicos conhecidos

Ordenados por risco. Todos verificados no código.

### Resolvido

- [x] **Sem testes de integração.** `integration_test/` tinha só um README
      planejando um teste que dependia de rede e credenciais. Agora são 18
      testes sobre um PowerSync real, rodando no CI — e a glue que o gate de
      cobertura exclui deixou de ser um buraco.
- [x] **Entidade `Account` incompleta.** Tinha 6 campos; agora tem os cinco que
      o PRD §5.2 pedia, `linked_space_id` inclusive (a coluna existia na
      migration e no schema PowerSync desde julho, sem chegar à entidade). Com
      isso a conta deixa de ser um registro sem uso: dá para cadastrar, editar e
      excluir pela aba Perfil.
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

- [x] **O app inteiro mostrava widget do Material em inglês.** Não havia
      `localizationsDelegates`, então todo texto que vem do Flutter (e não do
      nosso código) saía em inglês: o seletor de data do prazo da meta aparecia
      como "Fri, Jan 1 / January 2027 / Cancel / OK" no meio de um app em
      português. Nenhuma revisão de código pegaria — o texto não está no repo. Só
      rodar e olhar. Corrigido com `flutter_localizations` e `pt_BR` como único
      idioma declarado.
- [x] **`AppEmptyState` esticava até a borda da tela.** O `Column` não tinha
      `mainAxisSize.min`, então o card só ficava do tamanho certo dentro de um
      `ListView` (que dá altura infinita). Num `Center` de tela cheia — o caso da
      aba Poupança vazia, e também do "Sincronizando" da home — ele virava uma
      moldura do tamanho da tela e lia como caixa de placeholder.
- [x] **`AmountDisplay` estourava com valor de cinco dígitos.** A partir de
      `R$ 8.000,00`, 40px mono não cabia na largura de uma folha em tela de
      390px, e o Flutter pintava a faixa de overflow — em **qualquer** folha que
      usasse o widget, registro rápido e orçamento incluídos. Ninguém tinha
      notado porque nenhum teste digitava um valor grande. Agora um `FittedBox`
      reduz a escala em vez de vazar. **Lição transferível:** teste de entrada de
      valor precisa de um valor grande, não só de `R$ 12,34`.

### Médio

- [ ] **A meta não sabe que o gasto aconteceu.** Guardar valor é um evento
      próprio (`savings_contributions`), e registrar um lançamento
      `TransactionType.savings` **não** cria contribuição nenhuma — são dois
      caminhos que hoje não se falam. Quem usa os dois vê o dinheiro sair na
      lista e a meta não andar. As saídas são fazer o lançamento de poupança
      oferecer a meta no momento do registro, ou derivar contribuição de
      lançamento com conta alvo de poupança. É decisão de produto: o segundo
      caminho é o que a RN-3.2 chama de detecção, e ela foi desenhada para o
      Open Finance, não para lançamento manual.
- [ ] **Meta pausada não tem como ser pausada pela UI.**
      `SavingsGoalStatus.paused` existe no schema e no domínio, os providers já a
      excluem da lista, mas a folha só grava `active`. Uma meta que incomoda hoje
      só sai por exclusão, que apaga o histórico junto.
- [ ] **Excluir contribuição não existe na UI.** O repository tem
      `deleteContribution` (com teste), mas nenhuma tela chama: um valor digitado
      errado só sai excluindo a meta inteira. O desenho pendente é o gesto —
      arrastar a linha ou tocar e confirmar.
- [ ] **`GoalProgress` descarta silenciosamente aporte em outra moeda.** Somar
      BRL com USD lançaria e derrubaria a lista toda por causa de uma linha, e
      por isso a linha é ignorada. Não acontece hoje (o formulário só cria na
      moeda da meta), mas quando a Pluggy trouxer conta em outra moeda o valor
      vai desaparecer do progresso **sem aviso**. Mesma família do débito de
      moeda em `accountsNetBalance`, e a saída provavelmente é a mesma: dizer na
      tela que há valor fora da moeda em vez de omiti-lo.
- [ ] **Saldo de conta não reconcilia com lançamento.** É snapshot por decisão,
      e agora a divergência é visível: gastar R$ 50 na conta corrente não muda
      o saldo mostrado. Mitigado por `balance_as_of` — a tela diz de quando o
      número é —, mas a divergência continua. As saídas são reconciliação pelo
      Open Finance (Fase 1) ou um "saldo estimado" derivado exibido ao lado do
      informado. Decisão de produto, não de código.
- [ ] **Lançamentos antigos ficaram sem conta.** O padrão de conta única só
      vale para lançamento novo; nada preencheu o histórico. Um "atribuir os
      lançamentos sem conta a esta" resolveria de uma vez, mas é palpite sobre
      dado passado — hoje o caminho é editar um a um.
- [ ] **`profiles` sem `username`.** O PRD pede `username` **unique** (handle
      público do grafo social), `pix_key`, `avatar_url`, `phone`,
      `subscription_tier`. Nada é Fase 0, mas `username unique` é o campo mais
      caro de adicionar depois (backfill + escolha de handle para contas
      existentes). Vale decidir se entra no cadastro desde já.
- [ ] **O upload ao Postgres não é testado automaticamente.** Os testes de
      integração param na camada local; provar que a linha sai da fila e chega
      ao Supabase continua sendo passo manual no simulador. Automatizar exige um
      projeto Supabase só para teste, com dados descartáveis.
- [ ] **Golden tests ausentes.** Depende de empacotar as fontes primeiro (abaixo).
- [ ] **A flag de onboarding é por aparelho e some no logout.** Fica em tabela
      `localOnly`, e `disconnectAndClear()` apaga junto. Consequência: trocar de
      conta no mesmo aparelho mostra a apresentação de novo (defensável), e
      reinstalar também (menos defensável). Levar para `profiles` exigiria
      migration + coluna no schema do PowerSync + republicar sync rules.
- [ ] **Remover/editar categoria não existe na UI.** `CategoriesRepository`
      tem `delete` (com guarda para não apagar categoria de sistema), mas a folha
      só cria: uma categoria criada por engano fica permanente, só sai por SQL.
      O desenho pendente é permitir remover **apenas categoria sem lançamento
      algum** — o caso "tem lançamento" é pergunta de produto (reatribuir?
      deixar sem categoria?), o caso "recém-criada por engano" é trivial.
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
      telas multiplicarem os pontos de uso. O formulário de categoria já oferece
      nove chaves (`CategoryIcons.selectable`), então trocar de set agora custa
      mais que antes.
- [ ] **O FAB "Novo limite" é o único componente que lê como Material padrão.**
      Visto no simulador. Vale passar pela rodada de design em vez de eu
      arbitrar.
- [ ] **A fila de categorias corta o último chip visível** contra o chip "Nova"
      ancorado. Funciona, mas o corte parece defeito de renderização. **A saída
      agora existe**: `ScrollEdgeFade`, criado na fatia de metas, é exatamente
      isso — falta aplicá-lo aqui.
- [ ] **A folha de editar conta corta a última fileira do teclado.** Visto no
      simulador: com o botão "Excluir conta" no rodapé fixo sobra menos altura,
      e o `0` fica pela metade. A folha de meta resolveu o mesmo problema com
      **campos rolando e ações em rodapé fixo** (mais a divisão em dois passos);
      aplicar o mesmo desenho aqui fecha este débito e o de cima.
- [ ] **Conta é sempre em BRL.** A entidade e o schema carregam `currency`, mas
      o formulário não oferece escolha. Só incomoda quando houver conta em outra
      moeda; até lá, `accountsNetBalance` esconde o total se as moedas
      divergirem, em vez de somar coisas diferentes.

---

## Ambiente de desenvolvimento

| Item | Estado |
|---|---|
| macOS desktop | ✅ Roda. Entitlement `network.client` corrigida no PR #10. |
| iOS Simulator | ✅ Xcode 26.1.1. Verificado rodando de fato: `fvm flutter build ios --simulator --debug` + instalar o `Runner.app`. |
| Supabase local | ✅ Configurado nas portas 553xx (offset +1000, coexiste com `finance-dashboard`). Exige Docker de pé. |
| **PowerSync** | ✅ Instância Cloud (ambiente Development) ligada ao Supabase da nuvem, com as sync rules do repo publicadas. ⚠️ **Publicar é manual**: o arquivo do repo não sobe sozinho, e regras velhas se manifestam como tabela vazia no cliente sem erro nenhum. **Coluna nova não exige republicar** — os buckets usam `select *`, e a fatia de contas confirmou isso rodando: as quatro colunas novas chegaram ao SQLite local sem tocar no dashboard. Tabela ou bucket novo, sim. |
| **Supabase (nuvem)** | ✅ Projeto `ivfcypfljxvwkvnvmuum`, 7 migrations aplicadas, 10 categorias de sistema semeadas, 7 tabelas com `REPLICA IDENTITY FULL` na publication `powersync`. É o que o `env/dev.json` usa. |
| Web (Chrome) | ⚠️ Compila, mas falta `sqlite3.wasm` + worker em `apps/finance/web/`. `PowerSyncService.open()` falharia. |
| Android | ⚠️ Três bloqueios: `cmdline-tools` ausente, nenhum AVD criado, e o `env/dev.json` não serve (no emulador o host é `10.0.2.2`, não `127.0.0.1`, e o Android 9+ bloqueia cleartext — o `AndroidManifest.xml` não tem exceção). Precisaria de `env/dev-android.json` + network security config. |

---

## Questões abertas do PRD (§15)

| # | Questão | Status |
|---|---|---|
| 1 | Regime de renda para metas percentuais | ✅ **Respondida** — a renda é a soma dos lançamentos `income` do mês em foco, e a tela mostra de onde o número saiu. Nada é declarado à parte, então nada envelhece calado; o custo é que sem receita lançada não há base, e a tela diz isso em vez de exibir 0% |
| 2 | Algoritmo de simplificação de dívidas | Aberta. `Money.allocate()` já resolve o **split** de uma despesa (RN-2.1); a minimização de transferências entre membros (RN-2.2) é problema distinto e segue em aberto |
| 3 | Provedor de Open Finance | ✅ **Respondida** — Pluggy, server-side ([ADR 0005](adr/0005-open-finance-pluggy-server-side.md)). O PRD está desatualizado neste ponto |
| 4 | IA de categorização: modelo próprio vs. API | Aberta |
| 5 | Detecção de poupança — falsos positivos | Aberta, e agora com meia resposta no schema: `confirmed=false` existe para a detecção **propor** sem contar, e só o sim do usuário move o progresso. A heurística de detecção em si segue em aberto e é da ingestão Pluggy |
| 6 | Limite do Open Finance no grátis (1 ou 2 contas) | Aberta — depende de dados de conversão |
| 7 | Household com 3+ pessoas | Aberta. O schema **já suporta** (`space_members`); é decisão de UX |
| 8 | Moderação de feed/comentários | Aberta — Fase 3 |
| 9 | Cadência de notificações | Aberta — Fase 3 |
| 10 | Gamificação vs. saúde financeira | Aberta — princípio de produto, revisitar na Fase 1 |

---

## Referências

- [`CLAUDE.md`](../CLAUDE.md) — como trabalhar no repo (toolchain, comandos,
  Definição de Pronto, fluxo git)
- [`docs/adr/`](adr) — decisões de arquitetura e seus porquês. O mais recente é
  o [0007](adr/0007-agregado-derivado-vs-coluna.md): agregado é derivado, não
  coluna
- **PRD**: `PRD.pdf` na raiz (git-ignored — 11,7 MB). É a fonte de *o quê* e
  *por quê*; este arquivo é o *onde estamos*
- [`docs/pluggy-api-reference.md`](pluggy-api-reference.md) — referência da API do
  agregador
- Design system visual: projeto `Finance App — Design System` no Claude Design.
  Os previews são HTML; o que sincroniza com o Dart é a **especificação**, não o
  código
