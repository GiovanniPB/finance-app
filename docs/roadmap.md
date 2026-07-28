# Roadmap e estado do projeto

Documento vivo. O **PRD** define *o quê* e *por quê*; este arquivo registra
*onde estamos*. Atualize junto com o PR que muda o estado.

- Última atualização: **2026-07-28**
- Branch de trabalho atual: `feat/open-finance-fundacao`. O PR #24 (segurança e
  idioma) está **mergeado**. Os únicos outros PRs abertos são quatro do
  dependabot (#1, #2, #8, #9), deixados para depois por decisão; os dois de pub
  (`sqlite3`, `sqlite_async`) tocam a camada do PowerSync e merecem uma passada
  pelos testes de integração.
- ⚠️ **Pendência operacional que bloqueia o Open Finance no cliente:** as sync
  rules ganharam `open_finance_connections` e **não foram publicadas** no
  dashboard do PowerSync. Tabela nova exige publicação manual, e o sintoma de
  esquecer é tabela vazia **sem erro nenhum**.

---

## Estado em uma frase

**A Fase 1 começou pelo Pilar 3, e a fatia de poupança está fechada.** A Fase 0
está fechada (apresentação, gasto em três toques, edição, orçamento com alerta
em 80% e 100%, categoria própria, troca de espaço, contas completas), o
lançamento sabe de que conta saiu, e a camada local tem 31 testes de integração
rodando no CI contra um PowerSync de verdade.

Agora dá para **criar meta por objetivo, valor fixo mensal ou percentual da
renda, guardar valor e ver progresso** numa aba própria (Poupança, no lugar do
placeholder Social) — e **guardar dinheiro finalmente aparece no resto do app**:
a contribuição e o lançamento `savings` nascem juntos, então o valor sai do saldo
gastável, entra no total de saídas do mês e aparece na lista. Meta pode ser
pausada e retomada, e contribuição digitada errado pode ser removida.

A detecção automática de contribuição fica pendente do Open Finance — o resto da
Fase 1 é Open Finance (infra nova, credenciais Pluggy), streaks/badges e
categorização por IA.

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
6. Antes de mexer em `transactions` ou em poupança, leia
   [ADR 0008](adr/0008-guardar-dinheiro-e-um-evento-com-duas-faces.md). Guardar
   dinheiro grava **duas** linhas na mesma transação, e a contribuição é a dona
   do evento — a folha de lançamento se recusa a editar o que pertence a uma
   meta.
7. Para rodar: **não precisa de Docker.** O `env/dev.json` aponta para um
   Supabase e um PowerSync **na nuvem** (o `supabase start` local existe para
   testar migrations, não para rodar o app).
   `cd apps/finance && fvm flutter run -d iphone --target lib/main_dev.dart --dart-define-from-file=../../env/dev.json`.
   Criar conta é passo manual.
8. **Nunca aplique schema na nuvem por fora de `supabase db push`.** O
   `apply_migration` do MCP grava um histórico que o repo não reproduz — leia a
   seção "A armadilha do histórico de migrations" antes de tocar em schema.
9. **Se as telas ficarem vazias ou o registro rápido travar em "nenhuma
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

## Onde retomar

Estado em 2026-07-28, fim da sessão:

0. **Publicar as sync rules no dashboard do PowerSync.** É o primeiro passo da
   próxima sessão, e sem ele o resto do Open Finance não tem como funcionar no
   cliente: `open_finance_connections` é **tabela nova**, e tabela nova não sobe
   sozinha. Cole o `powersync/sync_rules.yaml` no editor de Sync Rules e faça
   Deploy. Para conferir depois, inspecione `ps_buckets` no SQLite local do app.
1. **A exposição das funções está fechada, e o advisor caiu de 10 WARN para 1.**
   O único que sobrou é o toggle de **proteção de senha vazada** no dashboard —
   um clique, sem código nem migration. Nada mais de segurança pende no repo.
   O advisor também passou a mostrar **1 INFO** (`rls_enabled_no_policy` em
   `webhook_events`), que é o desenho pretendido e não um defeito: RLS ligada com
   zero policies é justamente como se diz "server-only". Não "conserte"
   adicionando policy.
2. **Ver o app rodando ficou pela metade** (item herdado, ainda válido). O build
   e o launch funcionaram no iPhone 17 Pro, o app chegou à tela de login, e o
   login é passo manual. O roteiro que ainda não foi percorrido: a folha
   "Guardei um valor" com o campo "Saiu de"; o lançamento de poupança na lista
   (ícone próprio + "Poupança" na segunda linha); o toque nele abrindo **em
   leitura** com o caminho para a meta; a confirmação de remover contribuição
   avisando que o lançamento sai junto; pausar/retomar meta; a seção "Suas
   categorias" no Perfil; e o desvanecimento na fila de categorias. **O banco
   confirma que esse roteiro não foi percorrido**: há 2 metas e **zero**
   contribuições no Postgres.
   Agora há um segundo motivo para percorrê-lo: a mensagem de erro de login
   traduzida só se vê rodando (digite a senha errada e leia a frase).
3. **A cadeia de migrations continua sem ter sido replicada do zero.** A nova
   `20260728030625` rodou num Postgres de verdade (`supabase db push`, e a
   verificação como papel `authenticated` passou), mas `supabase db reset` — as
   **dez** em sequência num banco vazio — segue pendente por exigir Docker. É o
   débito médio mais antigo e o único que ainda separa "aplica sobre o schema
   atual" de "o repo descreve o banco".
4. **Fora do repo, pendente com o usuário:** o toggle de proteção de senha
   vazada, e **rotacionar as credenciais de Postgres, Redis e partnr** que um
   `claude mcp list` imprimiu em texto claro na sessão de 2026-07-28. Esta
   segunda é a mais urgente das duas e não depende do projeto.

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

### Concluído na fatia de fechamento da poupança (branch `feat/poupanca-fechamento`)

| Item | Onde |
|---|---|
| Migration `savings_contributions.transaction_id` (FK `on delete cascade`, `unique`) e o trigger de espaço validando o lançamento | `supabase/migrations/20260728000822_savings_contribution_transaction.sql` |
| Coluna e índice no schema PowerSync (**sem republicar sync rules** — os buckets usam `select *`) | `packages/database/lib/src/schema.dart` |
| `addContribution` grava **lançamento + contribuição** numa `writeTransaction` | `.../savings/data/savings_repository_impl.dart` |
| `deleteContribution` recebe a entidade e leva o lançamento junto | idem |
| `SavingsSql.insertTransaction` / `deleteTransaction` (SQL de `transactions` mora aqui por causa da atomicidade) | idem |
| Folha "Guardei um valor" com a conta de origem (`AccountPicker` + padrão de conta única) | `.../savings/presentation/contribution_sheet.dart` |
| Pausar/retomar meta por interruptor na folha de edição | `goal_form_sheet.dart`, `goal_form_controller.dart` |
| Seção de metas pausadas na aba, e detalhe que cala a cobrança | `savings_page.dart`, `goal_detail_page.dart` |
| Remover contribuição por toque na linha + confirmação | `goal_detail_page.dart` |
| Folha de edição de lançamento recusa editar o que pertence a uma meta | `.../transactions/presentation/transaction_edit_sheet.dart` |
| `pausedGoalsProvider` e `goalByTransactionIdProvider` | `.../savings/presentation/savings_providers.dart` |
| Lista de lançamentos mostra "Poupança" e ícone próprio | `.../transactions/presentation/transaction_list.dart` |
| 17 testes novos da fatia + 4 de integração | `test/features/savings/`, `test/features/transactions/`, `test_integration/savings_persistence_test.dart` |

**O enunciado do débito estava errado, e descobrir isso mudou a solução.** O
roadmap dizia que "registrar um lançamento `TransactionType.savings` não cria
contribuição nenhuma". Só que **nada no app produzia `savings`**: os dois
segmentos (registro rápido e edição) têm duas posições e só emitem
`expense`/`income`. O buraco real era o inverso — "Guardei um valor" gravava só a
contribuição, e guardar R$ 500 não mexia no saldo, não entrava em
`MonthSummary.outflow` e não aparecia na lista. O tipo `savings` existia
exatamente para esse evento e ninguém o criava.

Cinco decisões que não se leem no código:

- **Guardar dinheiro é um evento com duas faces**, não dois eventos que se
  falam. As duas linhas nascem na mesma `writeTransaction`, e o vínculo vive na
  **contribuição** (`transaction_id`), não no lançamento: existe lançamento sem
  meta em ~100% da tabela mais movimentada do app, e uma coluna
  `savings_goal_id` lá seria nula em quase toda linha.
- **A assimetria das exclusões é deliberada.** Remover a contribuição leva o
  lançamento (o dinheiro não saiu). Excluir a **meta** apaga as contribuições e
  **deixa os lançamentos de pé** (o dinheiro saiu de verdade; quem desistiu foi
  a meta). Apagar o extrato porque a meta foi abandonada reescreveria o passado
  financeiro do usuário.
- **O lançamento de poupança não é editável pela folha de lançamento.** Mudar o
  valor lá faria a meta contar R$ 500 e o extrato mostrar R$ 300; excluir lá
  deixaria a meta com progresso que o extrato não explica. A folha detecta o
  vínculo e vira leitura, com um botão para a meta. **O que trava é o vínculo,
  não o tipo** — um `savings` sem contribuição (o que a ingestão da Pluggy pode
  produzir) segue editável.
- **Poupança não tem categoria, de propósito.** Atribuir uma faria o valor
  debitar um orçamento — o usuário veria o limite de "Alimentação" andar porque
  guardou dinheiro. A descrição recebe o nome da meta, senão a linha apareceria
  como "Sem descrição"; e a lista diz "Poupança" no lugar da categoria.
- **Pausar é um campo do formulário, não uma ação própria.** Um botão "Pausar"
  que gravasse e fechasse a folha faria quem trocou o nome **e** pausou perder a
  troca do nome sem aviso. Interruptor + Salvar preserva as duas coisas. E
  `pausedGoalsProvider` existe porque `goalProgressListProvider` filtra pausadas:
  sem uma lista própria, pausar seria um esconder sem volta.

**A conta que a folha pergunta é a de origem** ("Saiu de"), não a de destino — o
destino já é a meta. É o mesmo padrão de conta única do registro rápido, com
`accountTouched` distinguindo "ainda não escolhi" de "tirei de propósito".

### Concluído na fatia de limpeza de débitos (branch `chore/limpeza-de-debitos`)

| Item | Onde |
|---|---|
| `CategoriesRepository.update` e `countUsage`; `delete` recusa categoria em uso com a contagem na mensagem | `.../categories/data/categories_repository_impl.dart` |
| Folha de categoria vira criar **ou** editar, com excluir sob confirmação | `.../categories/presentation/category_form_sheet.dart`, `category_form_controller.dart` |
| Seção "Suas categorias" na aba Perfil, espelhando a lista de contas | `.../profile/presentation/profile_page.dart` |
| `userCategoriesProvider` — só as criadas pelo usuário | `.../categories/presentation/categories_providers.dart` |
| `ScrollEdgeFade` ganha `axis`, e a fila de categorias ganha o desvanecimento | `packages/design_system/.../scroll_edge_fade.dart`, `category_picker.dart` |
| `tapVisible` e o fake de categorias promovidos ao harness (cinco e três cópias, zero agora) | `test/helpers/app_harness.dart` |
| `pumpScreen` aceita `categoriesRepository` injetado | idem |

Três decisões que não se leem no código:

- **Categoria vive no Perfil, não no `CategoryPicker`.** O picker aparece no
  registro rápido, que tem orçamento de três toques; pendurar gerenciamento ali
  (long-press, por exemplo) esconderia uma ação destrutiva atrás de um gesto que
  ninguém descobre. O Perfil já é a superfície de gerenciamento — contas moram
  lá pelo mesmo motivo.
- **A seção lista só categoria de usuário.** As dez de sistema não são editáveis
  (a RLS bloqueia, e o nome delas é vocabulário compartilhado entre espaços);
  mostrá-las seria oferecer dez linhas que não respondem ao toque.
- **A recusa por categoria em uso não é pré-checada na folha.** O repository já
  devolve a contagem na mensagem, e ela aparece na folha, que fica aberta.
  Pré-checar economizaria um toque ao custo de a mesma frase existir em dois
  lugares — e é a frase que diz ao usuário o que fazer.

**Dois itens saíram do escopo, e por quê.** Orçamento semanal é feature, não
limpeza: `BudgetPeriod.weekly` persiste, mas exibir "R$ 200/semana" ao lado de
"R$ 1.200/mês" e decidir qual semana é "a atual" quando o mês em foco não é o
corrente é desenho novo. E o FAB "Novo limite" continua fora porque o próprio
débito pede rodada de design em vez de arbitragem.

### Concluído na fatia de segurança e idioma (branch `fix/rls-privada-e-auth-em-portugues`)

| Item | Onde |
|---|---|
| Migration que cria o schema `private` e move `is_space_member`, `has_space_role` e `is_space_owner` para lá | `supabase/migrations/20260728030625_rls_helpers_schema_privado.sql` |
| `revoke execute` de `handle_new_user` e `set search_path = ''` em `set_updated_at` | idem |
| Regra no guia operacional: policy nova chama `private.…` | `CLAUDE.md` §5 |
| `authErrorMessage` — tradução do erro de auth por código, na fronteira da `data` | `.../auth/data/auth_error_message.dart` |
| Os dois `AuthFailure(e.message)` do repository passam a traduzir | `.../auth/data/auth_repository_impl.dart` |
| 11 testes do tradutor + o teste do repository afirmando o novo contrato | `test/features/auth/auth_error_message_test.dart` |

Três decisões que não se leem no código:

- **Mover de schema em vez de recriar as policies.** Referência de policy é
  gravada por OID, não por nome (`pg_policy` guarda a expressão já analisada),
  então `alter function … set schema` levou as 27 policies junto sem tocá-las.
  Recriar uma a uma seriam trezentas linhas de diff para o mesmo resultado, e
  cada policy reescrita é uma chance nova de errar um `using` de tabela
  sensível.
- **O `grant` que sobra na migration é deliberado.** O que fecha a porta é o
  schema não estar em `config.toml` — o PostgREST só roteia `/rest/v1/rpc/` para
  os schemas que expõe. Conceder `usage`/`execute` explicitamente tornou
  irrelevante uma pergunta que não se responde sem um Postgres na mão (se a
  avaliação de policy checa `EXECUTE` contra o papel da sessão), em vez de
  apostar numa das respostas.
- **A tradução casa por código, não por texto, e não pelo enum do SDK.** Código é
  contrato; frase é texto livre que muda entre versões do servidor. E o enum
  `ErrorCode` do gotrue 2.26.0 não lista `invalid_credentials` — depender dele
  faria o erro mais comum de todos cair no genérico.

**Medido na nuvem, não deduzido:** depois do `db push`, uma leitura assumindo o
papel `authenticated` com JWT de verdade devolveu os dados do dono e zero para um
`sub` estranho (que ainda vê as 10 categorias de sistema, como manda o
`is_system or is_space_member`). O advisor foi de 10 WARN para 1.

### Concluído na fatia de fundação do Open Finance (branch `feat/open-finance-fundacao`)

| Item | Onde |
|---|---|
| Migration: `open_finance_connections` (RLS por dono), `webhook_events` (server-only), `external_id` + `description_raw` em `transactions`, `connection_id` + `external_id` em `accounts`, uniques parciais | `supabase/migrations/20260728033219_open_finance_fundacao.sql` |
| Schema PowerSync das colunas e da tabela nova | `packages/database/lib/src/schema.dart` |
| Sync rules: conexão no bucket `user_owned` (**publicação manual pendente**) | `powersync/sync_rules.yaml` |
| Primeira Edge Function do projeto: `pluggy-connect-token` | `supabase/functions/pluggy-connect-token/index.ts` |
| `verify_jwt` declarado por função | `supabase/config.toml` |
| README das functions: segredos, deploy e o que **não** foi feito | `supabase/functions/README.md` |
| Revisão do ADR 0005: allowlist não-bloqueante e `external_id` único | `docs/adr/0005-*.md` |
| Widget do Pluggy Connect **internalizado**, com as guardas que o pacote oficial não tem | `.../open_finance/presentation/pluggy_connect/` |
| 9 testes de integração da fundação + 28 testes das guardas e do parser | `test_integration/open_finance_persistence_test.dart`, `test/features/open_finance/` |

Quatro decisões que não se leem no código:

- **A conexão é do usuário, não do espaço.** Escopada por `owner_id` como
  `accounts`: o `clientUserId` que vai para a Pluggy é `auth.uid()`, o
  consentimento é pessoal, e quem revoga é o titular. Um household vê as
  **contas** vinculadas, não a credencial que as alimenta.
- **Dois campos de status.** `status` é vocabulário nosso, curto e estável, que é
  o que a UI lê; `provider_execution_status` guarda o texto cru da Pluggy. Mapear
  os mais de doze `executionStatus` deles para estados de tela faria a UI mudar
  quando o fornecedor renomeasse um enum.
- **`webhook_events` é server-only, e o jeito de dizer isso é nenhuma policy.**
  Ela também não é fila: é o log que garante idempotência, porque a Pluggy
  re-tenta um webhook até nove vezes. A fila (pgmq) entra com o worker —
  instalar extensão antes de haver consumidor seria schema sem uso.
- **`clientUserId` sai do JWT verificado, nunca do corpo da requisição.** Se o
  cliente pudesse informá-lo, um autenticado criaria item no nome de outro.

**Os testes de integração documentam o que o banco local NÃO garante:** o check
de `status` não vale ali, e a `unique` de dedup não existe — tabela local do
PowerSync é view, e nem FK nem unique atravessam. A consequência prática está
escrita no teste: o worker de ingestão não pode delegar a dedup ao banco local.

**Medido na nuvem:** conexão visível só para o titular (0 para um `sub`
estranho), e `webhook_events` com uma linha real devolvendo **0** para
autenticado — a negação por ausência de policy funciona de fato, e não é a tabela
estar vazia.

#### O widget: internalizado em vez de adotado

O `flutter_pluggy_connect` é da própria Pluggy (publisher `pluggy.ai`), mas foi
lido inteiro (436 linhas) e **reescrito como código nosso**, por três lacunas
verificadas na 3.0.1: nenhum `onNavigationRequest` em lugar nenhum do pacote;
`launchUrl` recebendo URL do canal JS sem validar esquema; e mensagem de tipo
desconhecido caindo em `dynamic` sem tratamento. Some o argumento de seguir o
upstream — ele está parado desde nov/2024, tem 3 likes e não suporta web.

Três coisas que não se leem no código:

- **Uma dependência nova, não três.** `webview_flutter` foi a única a entrar no
  lockfile. `url_launcher` já estava na árvore transitivamente (via
  `supabase_flutter`, que a usa para OAuth) e só virou direta; `app_links` ficou
  de fora, porque no pacote oficial ela serve a um contorno que eles mesmos
  marcam com "TODO: find a better way to solve this".
- **Export condicional porque `webview_flutter` não suporta web**, e o CI compila
  `main_dev.dart` para web. Sem a divisão, uma tela de conexão bancária derrubaria
  um gate de CI que não tem relação com Open Finance. Verificado com um entrypoint
  descartável que forçou o compilador web a resolver o export.
- **A lógica de segurança vive em funções puras**, exercitáveis sem WebView, sem
  device e sem rede — e foi um desses testes que pegou um bug real: query
  malformada chega por **duas** famílias de exceção, e a primeira versão só
  tratava `FormatException`, deixando o `ArgumentError` de percent-encoding
  inválido subir até a tela.

### O que falta na Fase 1

| Item | Estado |
|---|---|
| Open Finance — schema | ✅ Fundação pronta e na nuvem (fatia acima). |
| Open Finance — `pluggy-connect-token` | Escrita, **não deployada e nunca exercitada contra a Pluggy**. Deno não está instalado, então o TS também não foi typecheckado: o primeiro `deploy` será a primeira compilação. |
| Open Finance — `pluggy-webhook` e `pluggy-sync-worker` | Não existem. O webhook precisa de `verify_jwt = false` e do header secreto; o worker é quem faz `GET /items` → `/accounts` → `/v2/transactions` e o UPSERT com as regras de propriedade de coluna. |
| Open Finance — widget Connect | ✅ Internalizado, com 28 testes das partes puras. **Nunca rodou num device**: nenhuma tela o instancia ainda. |
| Open Finance — caminho no app | Falta o que liga as pontas: domínio, dados e providers de conexão; a chamada à Edge Function; o botão "Conectar banco" no Perfil; e gravar `open_finance_connections` no `onEvent` de sucesso. |
| Detecção/confirmação automática de contribuição | Metade pronta: schema e UI existem; falta quem crie a linha (ingestão Pluggy). O `transaction_id` já espera por ela: a detecção pode ligar a contribuição ao lançamento importado |
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

- [x] **As funções de autorização saíram do schema exposto pela API**
      (2026-07-28). O advisor caiu de **10 WARN para 1**, e o único que sobrou é
      um toggle de dashboard (proteção de senha vazada). Duas coisas valem
      registro:

      **O enunciado do débito estava errado — de novo.** O roadmap dizia "três
      helpers de RLS expostos" mais "duas funções de trigger expostas". Rodando
      o `get_advisors` outra vez, a lista real era **quatro** funções executáveis
      (as três de RLS **mais** `handle_new_user`), e `set_updated_at` aparecia só
      por `search_path` mutável — ela não é `SECURITY DEFINER` e o PostgREST não
      expõe função que retorna `trigger`. É a segunda vez nesta série que a
      paráfrase de um achado envelhece pior que o achado: vale reler a fonte,
      não o resumo dela.

      **Duas saídas diferentes para o mesmo aviso, e o que decide é quem chama a
      função.** `handle_new_user` só é chamada por trigger, então `revoke execute`
      bastou — e o repo já tinha a prova disso na
      `savings_contributions_inherit_space`. As três de RLS são chamadas de
      dentro de 27 policies, então foram para um schema `private`, movidas com
      `alter function … set schema`: referência de policy é gravada por **OID**,
      não por nome, então as 27 seguiram a função sem serem recriadas.

      **A pergunta aberta ficou respondida ao aplicar.** A migration documentou
      não saber se a avaliação de uma policy checa `EXECUTE` contra o papel da
      sessão, e resolveu isso concedendo `usage`/`execute` explicitamente. Com o
      SQL na nuvem, a medição foi feita assumindo o papel `authenticated` com um
      JWT de verdade: leitura devolve os dados do dono (1 espaço, 8 lançamentos,
      2 metas, 11 categorias) e **zero** para um `sub` estranho, que ainda vê
      exatamente as 10 categorias de sistema. Ou seja: a RLS alcança a função em
      `private`, e continua isolando.
- [x] **Erro de autenticação não sai mais em inglês.** `authErrorMessage` traduz
      na fronteira da camada `data`, casando por `code` (contrato de API) em vez
      de por `message` (texto livre que muda entre versões do servidor). Não usa
      o enum `ErrorCode` do gotrue de propósito: a versão 2.26.0 **não lista
      `invalid_credentials`**, justamente o caso mais comum, então depender do
      enum faria o erro principal cair no genérico. Código desconhecido cai numa
      frase genérica em português em vez de mostrar o inglês — o `AppLogger` já
      guarda a exceção original, então não se perde diagnóstico.
- [x] **`get_advisors` rodou depois da mudança de schema** (2026-07-28): 10 WARN,
      **zero ERROR**. E o que importava confirmar passou: a
      `savings_contributions_inherit_space`, recriada pela `20260728000822` como
      `SECURITY DEFINER`, **não aparece** entre as funções expostas — o
      `revoke execute … from anon, authenticated, public` da migration segurou.
      Os avisos que sobraram são todos anteriores a esta fatia e estão nos
      débitos médios acima, mais um toggle de dashboard: **proteção de senha
      vazada desligada** (checagem contra o HaveIBeenPwned, um clique, sem
      migration).
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
- [x] **A meta não sabia que o dinheiro tinha saído** — e o enunciado do débito
      estava invertido. O texto antigo dizia que um lançamento
      `TransactionType.savings` não criava contribuição; na verdade **nada
      produzia `savings`** (os dois segmentos só emitem `expense`/`income`), e o
      buraco era o contrário: "Guardei um valor" gravava só a contribuição, então
      guardar R$ 500 não mexia no saldo, não entrava em `MonthSummary.outflow` e
      não aparecia na lista. Agora as duas linhas nascem juntas na mesma
      `writeTransaction`, ligadas por `savings_contributions.transaction_id`.
      **Lição transferível:** o enunciado de um débito envelhece junto com o
      código — vale reler o que ele afirma antes de agir sobre ele.
- [x] **Meta pausada não tinha como ser pausada pela UI.** Virou um interruptor
      na folha de edição (campo do formulário, não ação própria, para não perder
      edições pendentes), mais uma seção de pausadas na aba — sem ela, pausar
      esconderia a meta da única tela que leva ao detalhe dela. O detalhe de uma
      meta pausada também cala o que cobra: sem marca de ritmo, sem "faltam R$ X
      até tal data", sem projeção.
- [x] **Excluir contribuição não existia na UI.** Virou toque na linha +
      confirmação (não arrastar: não existe `Dismissible` em lugar nenhum do app,
      e inventar um gesto só aqui faria esta lista se comportar diferente de
      todas as outras). A confirmação nomeia o efeito colateral, e a frase muda
      quando não há lançamento ligado — prometer que "o lançamento sai junto" numa
      linha anterior à migration seria mentira.
- [x] **`AmountDisplay` estourava com valor de cinco dígitos.** A partir de
      `R$ 8.000,00`, 40px mono não cabia na largura de uma folha em tela de
      390px, e o Flutter pintava a faixa de overflow — em **qualquer** folha que
      usasse o widget, registro rápido e orçamento incluídos. Ninguém tinha
      notado porque nenhum teste digitava um valor grande. Agora um `FittedBox`
      reduz a escala em vez de vazar. **Lição transferível:** teste de entrada de
      valor precisa de um valor grande, não só de `R$ 12,34`.

### Médio

- [ ] **A cadeia de migrations nunca foi replicada do zero.** As duas mais
      recentes (`20260728030625` e `20260728033219`) subiram para a nuvem por
      `supabase db push`, então o SQL **rodou** num Postgres de verdade e foi
      aceito. Mas ninguém rodou `supabase db reset`, que aplica as **onze** em
      sequência num banco vazio. É a diferença entre "aplica sobre o schema
      atual" e "o repo descreve o banco" — e a segunda é a promessa que o
      `CLAUDE.md` faz. Exige Docker.

      Um detalhe que só aparece do zero: a `20260728030625` move três funções de
      `public` para `private` com `alter function`, e é **idempotente** por causa
      dos `if exists` — num banco vazio ela encontra as três em `public` (criadas
      pela `20260717120000`) e move; num banco já migrado, não faz nada. Rodar do
      zero é o que prova as duas metades.
- [ ] **As sync rules com `open_finance_connections` não foram publicadas.**
      O arquivo do repo mudou; o dashboard do PowerSync, não. Até publicar, a
      tabela existe no Postgres e no schema local e **nunca recebe linha** — sem
      erro em lugar nenhum. É a pendência que bloqueia todo o resto do Open
      Finance no cliente.
- [ ] **A Edge Function nunca foi compilada nem exercitada.** Deno não está
      instalado na máquina e `supabase functions serve` exige Docker, então o
      primeiro `supabase functions deploy` será a primeira compilação do
      `index.ts`. Os contratos seguem `docs/pluggy-api-reference.md` §3.3 e §3.4,
      mas nenhuma chamada real à Pluggy aconteceu. Mesma família da lição do
      `UPSERT` de orçamento: código que nunca rodou não é código que funciona.
- [ ] **O protocolo do widget Connect é contrato interno da Pluggy.** Os tipos de
      mensagem (`OAUTH_OPEN`, `LINK_OPEN`, `LOCATION`) e os nomes de evento na
      query (`SUCCESS`, `ERROR`, `CLOSE`, `LOGIN_SUCCESS`…) **não são
      documentados publicamente** — só se conhecem por leitura do fonte do
      pacote oficial. É a dívida que se aceitou ao internalizar o widget, e ela
      existiria igual usando o pacote deles (que também está parado). Se o fluxo
      parar sem nada nosso mudar, `pluggy_connect_event.dart` é o primeiro lugar
      a olhar.
- [ ] **O widget Connect nunca rodou num device.** As partes puras têm 28 testes,
      mas o WebView em si não foi instanciado: nenhuma tela o usa ainda, então
      não há prova de que o canal JS conversa, de que a allowlist não bloqueia
      algo legítimo do fluxo real, nem de que o salto para o OAuth do banco
      volta. Fecha junto com o caminho no app.
- [ ] **`Account` não conhece as colunas novas.** `connection_id` e `external_id`
      existem no Postgres e no schema PowerSync, mas não na entidade — então a UI
      não tem como distinguir conta importada de conta digitada, e a regra do ADR
      0005 (em conta de Open Finance o saldo é da Pluggy, não snapshot do
      usuário) não é aplicável ainda. É a versão pequena do débito de "entidade
      incompleta" já fechado, e fecha junto com a fatia do cliente.
- [ ] **O vínculo depende do cliente para não desincronizar no local.** No
      Postgres o `on delete cascade` garante que apagar o lançamento apaga a
      contribuição. As tabelas locais do PowerSync são views e não cascateiam:
      quem mantém as duas linhas juntas offline é a `writeTransaction` do
      repository. A UI fecha os caminhos conhecidos (a folha de lançamento recusa
      editar/excluir o que pertence a uma meta), mas SQL novo sobre
      `transactions` precisa lembrar disto.
- [ ] **Há uma janela em que o lançamento de meta parece editável.** A guarda da
      folha usa `goalByTransactionIdProvider`, que lê as contribuições
      sincronizadas. Num aparelho que recebeu o lançamento antes da contribuição
      (ordem de bucket não é garantida), a folha abriria editável por alguns
      instantes. Não acontece no caminho manual — as duas linhas nascem juntas —,
      mas vai acontecer quando a ingestão da Pluggy gravar dos dois lados.
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
- [ ] **Categoria com lançamento não tem como ser removida.** É o que sobrou do
      débito de remover categoria: a UI agora edita e remove, mas `delete`
      **recusa** categoria em uso, dizendo quantos lançamentos a usam. Resolver
      exige escolher entre deixar os lançamentos sem categoria e reatribuí-los —
      pergunta de produto, e a razão pela qual o caso ficou de fora.
- [ ] **Abas sem URL própria.** O `AppShell` usa `IndexedStack`, então deep link
      por aba não funciona. Quando virar requisito, trocar por
      `StatefulShellRoute` do go_router.
- [ ] **Ainda há fake duplicado em dois testes.** `tapVisible` e o fake de
      categorias foram promovidos ao harness (cinco e três cópias, zero agora),
      mas `quick_entry_sheet_test.dart` e `transactions_providers_test.dart`
      seguem com os próprios `FakeSpacesRepository`, `FakeTransactionsRepository`
      e `FakeBudgetsRepository` — por isso importam do harness com `show`, para
      não colidir. Migrá-los é mecânico; o que trava é que os fakes locais
      guardam argumentos (`lastFrom`, `lastTo`) que os do harness não expõem.
- [ ] **`savingsMonthTotal` e `MonthSummary.outflow` contam o mesmo dinheiro.**
      Guardar R$ 500 agora aparece nos dois: no total guardado do mês (aba
      Poupança) e nas saídas do mês (home). Está certo — são perguntas diferentes
      ("quanto guardei?" e "quanto saiu do saldo?") —, mas a home não distingue
      poupança de gasto no número agregado. Quando incomodar, o caminho é a home
      dizer "saídas, das quais R$ X guardados".
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
- [ ] **O teclado cortado na folha de conta não se reproduz no código.** O
      débito dizia para aplicar ali o desenho da folha de meta (campos rolando,
      ações em rodapé fixo) — e `git log -L` mostra que esse desenho **já existe
      desde `5aeb975`**, a própria fatia de contas: o `AmountKeypad` está dentro
      do `SingleChildScrollView`, então é alcançável rolando. Ou o corte era
      apenas visual (o mesmo "corte lê como defeito" que o `ScrollEdgeFade`
      resolve), ou já saiu junto de outra mudança. Reabrir só depois de ver
      rodando — mexer sem reproduzir seria adivinhar.
- [ ] **Conta é sempre em BRL.** A entidade e o schema carregam `currency`, mas
      o formulário não oferece escolha. Só incomoda quando houver conta em outra
      moeda; até lá, `accountsNetBalance` esconde o total se as moedas
      divergirem, em vez de somar coisas diferentes.

---

## Ambiente de desenvolvimento

| Item | Estado |
|---|---|
| macOS desktop | ✅ Roda. Entitlement `network.client` corrigida no PR #10. |
| iOS Simulator | ✅ Xcode 26.1.1. Verificado rodando de fato em 2026-07-28, no iPhone 17 Pro: `xcrun simctl boot <udid>` → `fvm flutter build ios --simulator --debug --target lib/main_dev.dart --dart-define-from-file=<abs>/env/dev.json` (133s) → instalar o `Runner.app`. O `--dart-define-from-file` **precisa de caminho absoluto** e vale no `build`, não só no `run`: `AppEnv` valida no boot. |
| **MCP do Supabase** | ⚠️ Armadilha custosa. Duas coisas o quebram: (1) um **header `Authorization` fixo** na config desliga o OAuth por completo — o erro é `OAuth fallback is disabled when headers.Authorization is set`, e reautorizar não resolve enquanto o header existir; (2) o consentimento OAuth é **por organização**, e o `Finance App` vive na org `Giovanni's Org` (`rwilajfjocmzyqyyikko`), não na `OTM Tecnologia`. Sintoma: `list_projects` devolve os projetos errados e `get_project(ivfcypfljxvwkvnvmuum)` dá `You do not have permission`. Para diagnosticar sem o MCP, use o CLI — `supabase orgs list` e `supabase projects list` mostram as quatro orgs da conta. |
| Supabase local | ✅ Configurado nas portas 553xx (offset +1000, coexiste com `finance-dashboard`). Exige Docker de pé. |
| **PowerSync** | ✅ Instância Cloud (ambiente Development) ligada ao Supabase da nuvem, com as sync rules do repo publicadas. ⚠️ **Publicar é manual**: o arquivo do repo não sobe sozinho, e regras velhas se manifestam como tabela vazia no cliente sem erro nenhum. **Coluna nova não exige republicar** — os buckets usam `select *`, e a fatia de contas confirmou isso rodando: as quatro colunas novas chegaram ao SQLite local sem tocar no dashboard. Tabela ou bucket novo, sim. |
| **Supabase (nuvem)** | ✅ Projeto `ivfcypfljxvwkvnvmuum`, as **11** migrations do repo aplicadas (`supabase migration list` casa nos dois lados — o `migration repair` da armadilha segurou), 10 categorias de sistema semeadas, 7 tabelas com `REPLICA IDENTITY FULL` na publication `powersync`. As funções de autorização vivem no schema `private`. É o que o `env/dev.json` usa. ⚠️ **Nunca aplique schema por outro caminho que não `supabase db push`** — ver a armadilha do histórico abaixo. |
| Web (Chrome) | ⚠️ Compila, mas falta `sqlite3.wasm` + worker em `apps/finance/web/`. `PowerSyncService.open()` falharia. |
| Android | ⚠️ Três bloqueios: `cmdline-tools` ausente, nenhum AVD criado, e o `env/dev.json` não serve (no emulador o host é `10.0.2.2`, não `127.0.0.1`, e o Android 9+ bloqueia cleartext — o `AndroidManifest.xml` não tem exceção). Precisaria de `env/dev-android.json` + network security config. |

---

## A armadilha do histórico de migrations (resolvida, e fácil de recriar)

Em 2026-07-28 um `supabase db push` falhou com **"Remote migration versions not
found in local migrations directory"**, apontando quatro versões que o remoto
conhecia e o repo não: `20260727192311`, `20260727195907`, `20260727224321`,
`20260727224349`.

**Nenhum arquivo com esses nomes jamais existiu no repo** — verificado com
`git log --all --diff-filter=A -- 'supabase/migrations/*'`. Não foi renomeação
nem squash.

A causa, reconstruída por horário (os nomes de versão são **UTC**, os commits
estavam em `-03`): as quatro nasceram de `apply_migration` do MCP do Supabase,
que aplica o SQL direto na nuvem e grava a versão com timestamp próprio. Cada
uma cai poucos minutos **antes** de um commit que adicionou um arquivo de
migration equivalente:

| Órfã (UTC) | Commit seguinte (UTC) | Arquivo local correspondente |
|---|---|---|
| `192311` | `5aeb975` 19:50 | `20260727210000_accounts_profile` |
| `195907` | mesma sessão | correção do mesmo SQL |
| `224321` | `2fa1e35` 22:45 | `20260727235500_savings_goals` |
| `224349` | 28s depois | idem, aplicada em duas partes |

O sinal que confirma: `20260727151151` (transações) tem horário coerente com a
geração real, enquanto `210000`, `230000` e `235500` são **redondos e à frente do
próprio commit** — nome escrito à mão depois de o SQL já ter subido por outro
caminho. Duas histórias paralelas para o mesmo DDL.

**A regra que evita isso:** schema deste projeto muda **só** por arquivo em
`supabase/migrations/` aplicado com `supabase db push`. `apply_migration` do MCP
serve para exploração num branch descartável, nunca no projeto que o
`env/dev.json` usa — ele grava um histórico que o repo não tem como reproduzir, e
`supabase db reset` deixa de descrever o banco.

Se acontecer de novo: `supabase migration list` mostra os dois lados,
`supabase migration repair --status reverted <órfãs>` limpa o histórico (não
desfaz DDL), e `--status applied <arquivos locais>` registra os equivalentes.
**Não** use `supabase db pull` aqui: ele achata as nove migrations comentadas num
arquivo só, e os cabeçalhos delas são documentação de verdade.

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
  o [0008](adr/0008-guardar-dinheiro-e-um-evento-com-duas-faces.md): guardar
  dinheiro grava lançamento **e** contribuição, e a contribuição é a dona do
  evento
- **PRD**: `PRD.pdf` na raiz (git-ignored — 11,7 MB). É a fonte de *o quê* e
  *por quê*; este arquivo é o *onde estamos*
- [`docs/pluggy-api-reference.md`](pluggy-api-reference.md) — referência da API do
  agregador
- Design system visual: projeto `Finance App — Design System` no Claude Design.
  Os previews são HTML; o que sincroniza com o Dart é a **especificação**, não o
  código
