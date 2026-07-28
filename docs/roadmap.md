# Roadmap e estado do projeto

Documento vivo. O **PRD** define *o quê* e *por quê*; este arquivo registra
*onde estamos*. Atualize junto com o PR que muda o estado.

- Última atualização: **2026-07-28**
- Branch de trabalho atual: `feat/streaks-e-badges`, a partir da `main`.
  **A pilha do Open Finance, a correção da ingestão, os débitos e a correção do
  mês estão mergeadas** (PRs #27 a #32). ⚠️ Fica registrada a armadilha que a
  pilha revelou:
  **PR empilhado não tem CI**, porque o workflow dispara só em `pull_request` para
  `main` — o #26 nunca teve check, e a verificação dele foi local, o que não é a
  mesma coisa. Os únicos PRs abertos são quatro do dependabot (#1, #2, #8, #9),
  deixados para depois por decisão; os dois de pub (`sqlite3`, `sqlite_async`)
  tocam a camada do PowerSync e merecem uma passada pelos testes de integração.
- ✅ **Sync rules publicadas** e **segredos da Pluggy configurados** (confirmado
  por `supabase secrets list`, que mostra só os digests). A Edge Function
  `pluggy-connect-token` está **deployada e no ar**: `POST` sem `Authorization`
  devolve 401 no gateway.

---

## Estado em uma frase

**O pipeline de Open Finance ingere dado de banco real: 2.076 lançamentos de
duas contas e dois cartões, com a direção conferida contra a fatura.** Foram os
dados — não os testes — que acharam os dois bugs da primeira passagem. A Fase 0
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

A **detecção automática de contribuição fechou o circuito no código**: entrada
numa conta marcada como alvo de poupança, com uma meta ativa apontando para ela,
vira contribuição `confirmed=false` ligada ao lançamento importado, e o card da
meta anuncia que há algo a confirmar. Ainda **não foi vista rodando** — o worker
precisa ser deployado.

**Streak e conquistas existem**, derivados do histórico e sem tabela nenhuma
([ADR 0009](adr/0009-conquista-derivada-ate-ser-anunciada.md)): a aba Poupança
mostra a sequência de semanas (que a segunda-feira não zera) e sete conquistas,
com a bloqueada dizendo o que falta em vez de exibir um cadeado. Da Fase 1 resta
só a **categorização por IA**.

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
9. **Antes de mexer na direção do lançamento importado, leia
   `supabase/functions/_shared/ingest.ts`.** A regra já foi trocada duas vezes,
   nas duas direções, e as duas vezes gravou dinheiro errado — porque cada uma
   foi tirada de **um** conector. A tabela-verdade medida nos dois está lá, com
   teste (`node --test 'supabase/functions/_shared/*.test.ts'`), inclusive o caso
   do sandbox que fica errado de propósito. Não "conserte" esse caso.
10. **Antes de criar tabela para streak, conquista ou qualquer marco, leia o
    [ADR 0009](adr/0009-conquista-derivada-ate-ser-anunciada.md).** Os dois são
    derivados do histórico de contribuição, e o PRD modela `achievements` que
    **de propósito** não existe. Ela só nasce na Fase 3, e para registrar que a
    conquista foi *anunciada* — não para guardar o que se calcula.
11. **Antes de mexer na detecção de poupança, leia `detectSavingsContribution`
    em `_shared/ingest.ts` e o item 5 do cabeçalho do worker.** Duas escolhas
    parecem defeito e não são: a regra propõe rendimento como aporte de
    propósito (a proposta não move dinheiro; o sim do usuário move), e só linha
    **recém-inserida** é proposta — reprocessar não repropõe, porque recusar uma
    proposta é apagá-la.
12. **Se as telas ficarem vazias ou o registro rápido travar em "nenhuma
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

0. **Duas fatias esperam para ser vistas rodando, e a segunda é grátis de
   conferir.** Streak e conquistas não dependem de deploy nenhum — são derivados
   do que já está no banco. Basta abrir a aba Poupança:

   - o bloco de sequência aparece com "Nenhuma sequência agora" enquanto não
     houver aporte confirmado (o banco mostrava **zero** contribuições);
   - guardar um valor deve acender "1 semana seguida" na hora;
   - a seção Conquistas mostra "0 de 7", e cada selo bloqueado diz o que falta;
   - o que **não** dá para ver sem esperar semanas é a sequência longa — o teste
     cobre isso, mas a tela com "12 semanas seguidas" nunca foi renderizada.

1. **A detecção de poupança está escrita e não foi vista rodando.** É a dívida
   mais fresca e a mais fácil de pagar errado. Para exercitá-la:

   1. deployar o worker (comando na seção da fatia; `functions deploy` é passo
      do usuário);
   2. no app, marcar uma conta conectada como **alvo de poupança** e criar uma
      meta **ativa** apontando para ela (a folha de meta oferece todas as contas
      no seletor "onde o dinheiro fica");
   3. provocar uma sincronização e conferir por SQL o `payload` do evento — os
      contadores `propostos`, `semMeta`, `metaAmbigua` e `moedaDivergente` dizem
      o que a regra decidiu, e `semMeta` alto é o sintoma de a meta não estar
      ligada à conta certa;
   4. ver no app a linha "1 aporte detectado a confirmar" no card da meta, e o
      progresso **não** se mover até o toque em Confirmar.

   Lembre que só **extrato novo** é proposto: os 2.083 lançamentos já ingeridos
   não viram proposta nenhuma, por decisão (ver o débito do backfill). Se nada
   aparecer, essa é a primeira hipótese — não um defeito da regra.

2. **Desconectar foi exercitado de verdade** (2026-07-28, iPhone 17 Pro). A
   `pluggy-disconnect` está deployada, e a passagem provou o que teste nenhum
   prova:

   | O que | Resultado |
   |---|---|
   | conexões | 3 → 1 (só a real) |
   | contas | 4 → 2, **renomeadas** para "Nubank" e "Ultravioleta" |
   | lançamentos do banco removido | 26 continuam existindo, `account_id` nulo |
   | lançamentos totais | 2.083, dos quais 2.050 em conta |

   A Pluggy aceitou o `DELETE /items`: a linha só é apagada depois de
   `revokeAccess` devolver `Ok`, então se a revogação tivesse falhado ela estaria
   lá. Os nomes editados sobreviveram, o que confirma que a ingestão não
   sobrescreve `name` depois do INSERT. E o extrato do banco removido continua
   existindo sem conta — o que a confirmação promete.

   **Um encadeamento que não foi projetado e saiu certo:** removida a conexão, as
   contas viram contas comuns, e aí "Excluir conta" reaparece nelas — foi assim
   que o dado de sandbox pôde ser limpo. Numa conta ainda importada o botão não
   existe.

3. **A home foi vista com 2.083 lançamentos, e achou dois bugs** (fatia acima):
   o dia 1º invisível e `transfer` somado como receita. O que **ainda não** foi
   visto é a **lista do mês** — 145 linhas em julho, com o rótulo
   "Transferência", o total do dia e o cabeçalho de saldo. `MoneyText` não tem
   `FittedBox` (só o `AmountDisplay` ganhou, depois de estourar com cinco
   dígitos), e agora há total de dia passando de R$ 10.000. Toque em "Ver tudo"
   na home.

   **E há um roteiro herdado que continua sem ser percorrido**, confirmado pelo
   banco: 2 metas e **zero** contribuições no Postgres. Falta ver a folha
   "Guardei um valor" com o campo "Saiu de"; o lançamento de poupança na lista
   (ícone próprio + "Poupança" na segunda linha); o toque nele abrindo **em
   leitura** com o caminho para a meta; a confirmação de remover contribuição
   avisando que o lançamento sai junto; pausar/retomar meta; a seção "Suas
   categorias" no Perfil; o desvanecimento na fila de categorias; e a mensagem de
   erro de login em português (digite a senha errada e leia a frase).

4. **O reparo da ingestão está feito e medido**, e o que a primeira ingestão
   real ensinou vale relido antes de mexer em `_shared/ingest.ts`:

   **A convenção de sinal depende do tipo de conta.** Em conta corrente,
   negativo saiu. **Em cartão é invertido**: compra é positiva, e negativo é
   abatimento de fatura. A doc oficial diz exatamente isso, e foi o que chegou do
   Nubank — 305 compras de cartão que a regra "o sinal manda" (tirada só do
   sandbox) gravou como **receita**. Duas regras já foram derivadas de um
   conector só, e as duas erraram: **uma amostra de tamanho um não é uma
   convenção.**

   **O cartão do sandbox continua errado, de propósito.** Ele manda compra como
   `CREDIT` **negativa** — inverte os dois campos ao mesmo tempo, o que é
   exatamente a assinatura de um pagamento de fatura. Nenhuma regra derivada da
   doc acerta esse caso e nenhum cruzamento o detecta. É fixture defeituosa; o
   que precisa estar certo é conta real. Está escrito no teste para ninguém
   "consertar" isso e quebrar produção de novo.

   **Crédito de cartão é `transfer`, não receita.** Pagar a fatura é dinheiro
   trocando de bolso: `transfer` não entra em `inflow` nem em `outflow`, e o
   gasto já foi contado quando a compra entrou. Sem isso, um pagamento de
   R$ 10.139,02 apareceria como receita do mês. Custo aceito: estorno também fica
   invisível no resumo.

   **1.433 lançamentos sumiram em silêncio, e a causa era a leitura.** O worker
   buscou 4 páginas de um cartão (1.750 transações) e só a última virou linha. Um
   `in.()` com 433 ou 500 UUIDs monta URL de 17 a 20 mil caracteres, e o `fetch`
   de dentro da Edge Function não consegue enviá-la; o erro virava `return 0`, que
   significa "nada a fazer", e a página era descartada contando-se como escrita.
   Hoje a leitura vai em pedaços de 100 (`READ_CHUNK`), o INSERT também, toda
   falha **lança**, e o resultado de cada página é gravado no `payload` do evento.

   **Duas explicações erradas antes da certa, e as duas por método.** A primeira:
   testei `in.()` com 500 UUIDs **do laptop**, deu HTTP 200 e descartei a hipótese
   certa — quem recusa não é o Kong, é o cliente HTTP do runtime da função. A
   segunda: com a hipótese boa descartada, culpei colisão de `external_id`, e
   `ON CONFLICT DO NOTHING` nem chega a rodar aqui — a `unique` é **parcial**, e o
   Postgres não infere índice parcial sem o predicado repetido, coisa que o
   `onConflict` do PostgREST não expressa (*"there is no unique or exclusion
   constraint matching the ON CONFLICT specification"*, em toda tentativa). As
   duas passaram por typecheck, lint e testes; o que as matou foi rodar.

   **`console.log` de Edge Function não é diagnóstico.** A saída não é legível
   por SQL nem pelo CLI desta versão, só pelo dashboard — a primeira
   instrumentação rodou e não houve como ler o resultado. Toda observação nova
   vai para o banco.

5. **A exposição das funções está fechada, e o advisor caiu de 10 WARN para 1.**
   O único que sobrou é o toggle de **proteção de senha vazada** no dashboard —
   um clique, sem código nem migration. Nada mais de segurança pende no repo.
   O advisor também passou a mostrar **1 INFO** (`rls_enabled_no_policy` em
   `webhook_events`), que é o desenho pretendido e não um defeito: RLS ligada com
   zero policies é justamente como se diz "server-only". Não "conserte"
   adicionando policy.
6. **A cadeia de migrations continua sem ter sido replicada do zero.** A nova
   `20260728030625` rodou num Postgres de verdade (`supabase db push`, e a
   verificação como papel `authenticated` passou), mas `supabase db reset` — as
   **dez** em sequência num banco vazio — segue pendente por exigir Docker. É o
   débito médio mais antigo e o único que ainda separa "aplica sobre o schema
   atual" de "o repo descreve o banco".
7. **Fora do repo, pendente com o usuário:** o toggle de proteção de senha
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

### Concluído na fatia do cliente de Open Finance (branch `feat/open-finance-cliente`)

| Item | Onde |
|---|---|
| `OpenFinanceConnection` + `ConnectionStatus` (com `unknown` tolerante) | `.../open_finance/domain/open_finance_connection.dart` |
| Interface e implementação do repository: `watchAll`, `requestConnectToken`, `save`, `delete` | `.../open_finance/{domain,data}/` |
| Providers: conexões, contagem de contas por conexão, conexões que pedem ação | `.../open_finance/presentation/open_finance_providers.dart` |
| Tela cheia do fluxo, com espera, falha e "Tentar de novo" | `.../open_finance/presentation/connect_bank_page.dart` |
| `ConnectionTile` espelhando a `AccountTile` | `.../open_finance/presentation/connection_tile.dart` |
| Seção "Bancos conectados" no Perfil, com re-consentimento por toque | `.../profile/presentation/profile_page.dart` |
| `Account.connectionId` / `externalId` / `isFromOpenFinance` — fecha o débito | `.../accounts/domain/account.dart` |
| `FakeOpenFinanceRepository`, `testConnection` e o helper `scrollTo` no harness | `test/helpers/app_harness.dart` |
| 33 testes novos (17 do repository, 10 da seção, 6 da tela) | `test/features/open_finance/` |

Cinco decisões que não se leem no código:

- **`ConnectionStatus.unknown` existe, e `AccountType.fromDb` lança.** A diferença
  é deliberada: quem escreve `status` é o **servidor**, e a tabela local é view —
  o `check` do Postgres não vale nela. Uma versão nova do servidor gravando um
  status novo faria a lista de bancos estourar num app antigo. Ele nunca é
  **escrito**: só existe na leitura.
- **A contagem de contas por conexão é derivada**, não guardada. Contador que
  precisa ser igual a uma contagem desincroniza offline — a mesma razão pela qual
  não existe `savings_goals.current_amount` (ADR 0007).
- **Só conexão que precisa de ação responde ao toque**, e o que ela abre é o
  re-consentimento. Um detalhe que apenas repetisse a linha seria toque sem
  resposta.
- **A distinção de estado na linha não é por cor.** Âmbar pertence ao orçamento e
  vermelho a limite estourado; usar qualquer um faria conexão parada ler como
  dinheiro em risco. Separam-na a forma do ícone e a frase da segunda linha.
- **Tela cheia, não folha** — a única do app. Quem desenha aqui é a Pluggy, com
  várias etapas e teclado; uma folha a meia altura obrigaria a rolar dentro de um
  WebView que já rola.

**`connection_id` e `external_id` entram na leitura de `Account` mas não no
`toColumns`**: são colunas da ingestão (ADR 0005), e um UPDATE do cliente que as
incluísse apagaria o vínculo na primeira edição de nome.

**O export condicional passou a ser exercitado de verdade.** Antes nada
alcançável importava o widget, então o build web nem o tocava. Agora
`ProfilePage → ConnectBankPage → pluggy_connect_view` está no grafo, e o build web
passa escolhendo o stub.

**Quatro testes do Perfil precisaram de scroll**: a quarta seção empurrou as
outras para fora do viewport, e `find.text` de item que o `ListView` não construiu
falhava como se a seção tivesse sumido. Virou o helper `scrollTo`, e `tapVisible`
agora rola sozinho quando o alvo ainda não existe.

### Concluído na fatia de ingestão (branch `feat/open-finance-ingestao`, PR #28)

| Item | Onde |
|---|---|
| `pluggy-webhook`: enfileira em `webhook_events`, sem confiar no payload | `supabase/functions/pluggy-webhook/index.ts` |
| `pluggy-sync-worker`: `GET /items` → `/accounts` → `/v2/transactions` (cursor) → escrita | `supabase/functions/pluggy-sync-worker/index.ts` |
| Instrumentação da convenção de sinal, gravada no `payload` do evento | idem |
| `PluggyNotFound` — 404 tem tipo próprio, porque não é falha: é fato | `supabase/functions/_shared/pluggy.ts` |

Quatro decisões que não se leem no código:

- **O header secreto do webhook não existe neste caminho, e o ADR pedia.** A
  Pluggy só envia `headers` customizados em webhook registrado por
  `POST /webhooks`; o nosso `webhookUrl` vai no Connect Token, e por ali o POST
  chega sem header algum. Exigi-lo recusaria 100% dos webhooks. A autoridade vem
  de três lugares que não dependem de quem chama: o payload nunca é confiado, só
  item que já existe é aceito, e `event_id` é `unique`.
- **pgmq não entrou.** `webhook_events` já tinha `processed_at`, `attempts`,
  `last_error` e índice parcial; pgmq guardaria os mesmos fatos num segundo lugar
  e criaria duas verdades para reconciliar.
- **`item/deleted` era inalcançável.** O worker fazia `GET /items/{id}` antes de
  olhar o tipo do evento, e para item deletado esse GET é 404 por definição —
  então o ramo que marcava a conexão como removida nunca executava, e três
  conexões ficaram `active` apontando para items mortos.
- **Lançamento importado nasce no espaço pessoal do dono**, não no espaço ativo
  da sessão: senão o mesmo extrato cairia em lugares diferentes conforme a aba
  que estivesse aberta quando o webhook chegou.

### Concluído na fatia de correção da ingestão (branch `fix/direcao-e-perda-na-ingestao`)

Duas correções que só a **primeira ingestão real** revelou, e nenhuma das duas
aparecia em teste porque as Edge Functions não tinham teste nenhum.

| Item | Onde |
|---|---|
| `_shared/ingest.ts` — as decisões puras da ingestão, com a tabela-verdade medida nos dois conectores | `supabase/functions/_shared/ingest.ts` |
| 16 testes das regras, rodando em `node --test` (sem Deno, sem Docker, sem rede) | `supabase/functions/_shared/ingest.test.ts` |
| Direção ciente do tipo de conta: em cartão o sinal é invertido, e crédito de cartão é `transfer` | idem |
| Escrita que falha **lança** em vez de devolver número; INSERT em pedaços com recuo linha a linha; contagem do `select` do que entrou | `pluggy-sync-worker/index.ts` |
| Resultado de cada página gravado no `payload` do evento (chegaram, filtradas, colididas, entraram) | idem |
| Lista de lançamentos nomeia "Transferência" e usa ícone próprio | `.../transactions/presentation/transaction_list.dart` |
| Gate de CI para as regras da ingestão | `.github/workflows/ci.yaml` |
| Referência da Pluggy corrigida nos campos `amount` e `type` | `docs/pluggy-api-reference.md` |

Cinco coisas que não se leem no código:

- **Uma amostra de tamanho um não é uma convenção.** A regra anterior foi tirada
  do sandbox e gravou 305 compras de cartão real como receita; a anterior a ela
  foi tirada da doc e gravou 27 compras de sandbox como receita. O que resolveu
  não foi escolher melhor entre `type` e sinal, foi perceber que **o tipo de
  conta é parte da regra**.
- **O erro do sandbox está escrito no teste como esperado.** Compra lá chega
  como `CREDIT` negativa, que é a assinatura exata de um pagamento de fatura —
  indistinguível. Documentar o caso errado é o que impede a terceira inversão.
- **A perda era a leitura, não a escrita — e eu construí a explicação errada
  primeiro.** Um `in.()` com 433 ou 500 UUIDs monta URL de 17 a 20 mil
  caracteres, e o `fetch` de dentro da Edge Function não consegue enviá-la:
  `TypeError: error sending request`. A versão antiga respondia a isso com
  `return 0` — que significa "nada a fazer" — e descartava a página contando-a
  como escrita.

  O erro de método vale mais que o bug: eu **testei** `in.()` com 500 UUIDs e deu
  HTTP 200, e descartei a hipótese. Testei do laptop contra o Kong; quem recusa é
  o cliente HTTP do runtime da função. Um teste do lugar errado produz uma
  conclusão com a forma de evidência, e ela me levou a uma segunda explicação
  (colisão de `external_id`) que passou por typecheck, lint e 16 testes antes de
  morrer no primeiro contato com o banco.
- **`ON CONFLICT DO NOTHING` não dá, e o motivo é o índice ser parcial.** Ele
  não seria o `upsert` que o ADR proíbe (não atualiza coluna nenhuma), mas o
  Postgres não infere índice parcial sem o predicado repetido no `ON CONFLICT`, e
  o PostgREST não o expressa. O substituto — pedaços de 100 com recuo linha a
  linha — dá o mesmo resultado e ainda **conta** as colisões, que o
  `DO NOTHING` engoliria. Descoberto reprocessando: a suposição de que daria
  passou pelo typecheck, pelo lint e por 16 testes.
- **A instrumentação respondeu, e a resposta foi "não".** `colididas` = 0 em
  todas as páginas: o `providerId` é único por transação, e a suspeita de que ele
  colapsasse parcela da mesma compra estava errada. Vale registrar que a suspeita
  nasceu de ler descrições (`Vindi *Casalarshop 8/12`) — plausível, e não é o
  mesmo que medido.

### Concluído na fatia de débitos do Open Finance (branch `chore/debitos-de-open-finance`)

| Item | Onde |
|---|---|
| `pluggy-disconnect` — cancela o acesso no banco (`DELETE /items/{id}`) | `supabase/functions/pluggy-disconnect/index.ts` |
| `verify_jwt` declarado para a função nova | `supabase/config.toml` |
| `OpenFinanceRepository.revokeAccess`, com a ordem "revoga, depois apaga" no contrato | `.../open_finance/{domain,data}/` |
| `ConnectionSheet` — folha de ações da conexão, com Reconectar e Remover banco | `.../open_finance/presentation/connection_sheet.dart` |
| Toda conexão passa a responder ao toque | `.../profile/presentation/profile_page.dart` |
| Conta importada: tipo e saldo viram fato, e excluir desaparece | `.../accounts/presentation/account_form_sheet.dart` |
| `revokeFailure`/`revoked` no fake de Open Finance | `test/helpers/app_harness.dart` |
| 16 testes novos (8 da folha, 4 do repository, 4 da conta importada) + 1 reescrito | `test/features/open_finance/`, `test/features/accounts/` |

Quatro decisões que não se leem no código:

- **"Remover banco" sem revogar seria mentira, e é por isso que existe função
  nova.** `DELETE /items/{id}` exige a API Key, que não sai do servidor. Apagar
  só a nossa linha deixaria o consentimento vivo no banco, a Pluggy
  sincronizando, e a tela afirmando que o acesso foi cancelado. Promessa falsa
  sobre acesso a dado bancário é pior que a ausência do botão.
- **A ordem é revoga → apaga, e o teste que garante isso é o da falha.** Na ordem
  inversa, a linha sai do app com o consentimento vivo e sem nada que aponte para
  ele: não há mais como cancelá-lo. Com revogação falhando, a linha **fica** e a
  folha mostra o erro.
- **Quem autoriza a revogação é a RLS, não um `if` na função.** A conexão é lida
  com o `Authorization` do chamador, então a policy decide. Uma checagem escrita
  na função seria uma segunda cópia da mesma regra, e cópias divergem.
  Consequência: item de outro usuário responde 404, não 403.
- **Conta importada não tem "Excluir", e não é zelo excessivo.** O worker insere
  quando não encontra o `external_id`, então excluir **recria** a conta com nome
  padrão, sem alvo de poupança nem espaço vinculado — e como a dedup de lançamento
  é por `account_id`, a conta nova reimportaria o extrato inteiro (1.750 linhas no
  caso real) enquanto o antigo ficaria órfão. Um toque viraria histórico
  duplicado.

**Visto rodando** (iPhone 17 Pro, contra Supabase e PowerSync reais): remover
banco com revogação de verdade, as contas do sandbox virando comuns e podendo ser
excluídas, e as duas contas reais renomeadas à mão sem a sincronização desfazer.

**Tipo e saldo aparecem como fato, não como campo desabilitado.** Campo cinza
convida a tocar e não responde; um bloco com o valor, a data e a frase "editar
aqui seria desfeito na próxima sincronização" diz o que está acontecendo. É o
mesmo desenho que a folha de lançamento usa quando detecta vínculo com meta.

### Concluído na fatia do mês que perdia o dia 1º (branch `fix/mes-perdia-o-primeiro-dia`)

Dois bugs achados **rodando com extrato de banco real**, um deles vivo desde a
fatia de transações.

| Item | Onde |
|---|---|
| `datetime()` nos dois lados do recorte de mês | `.../transactions/data/transactions_repository_impl.dart` |
| `MonthSummary` casa por tipo em vez de "o que sobrou" | `.../transactions/domain/month_summary.dart` |
| Teste de integração com a linha no formato da **sincronização** | `test_integration/local_persistence_test.dart` |
| Dois testes de `MonthSummary` e um do SQL atualizados | `test/features/transactions/` |

**O primeiro dia de todo mês estava invisível.** O PowerSync guarda o timestamp
como `2026-07-01 05:00:00.000Z` — com **espaço** — e o app comparava contra
`2026-07-01T00:00:00.000Z`, com **T**. Em texto, `' '` (0x20) < `'T'` (0x54):
toda linha do dia 1º reprovava no `>=` e sumia; a do dia 1º do mês seguinte
passava no `<` e entrava. Em julho/2026 isso escondeu 8 linhas e
**R$ 15.111,01 de despesa** do resumo.

**Duas escolhas de teste, juntas, deixaram isso sem cobertura por meses.** O
teste que existia (`o recorte por período não traz o mês vizinho`) escolhia 30 de
junho e 2 de julho — **evitava a fronteira** — e criava as linhas pelo
repositório, que escreve com `T`, então elas comparavam entre si sem conflito. O
teste novo insere SQL direto no formato da sincronização, e falha sem a correção
devolvendo **`tx-mes-seguinte` no lugar de `tx-primeiro-dia`**: as duas metades do
bug numa asserção.

**`transfer` era somado como receita.** `MonthSummary` fazia
`if (isOutflow) … else income += …`, o que era inofensivo enquanto nada no produto
produzia `transfer`. Com a ingestão gravando pagamento de fatura, a home exibiu
**R$ 10.641,79 de "Entradas"** que eram dinheiro trocando de bolso. Agora casa por
tipo: um tipo novo passa a não contar em nada, em vez de virar receita em
silêncio. E havia um teste **afirmando o comportamento errado** — chamava-se
"convenção da Fase 0" e protegia o bug.

Duas coisas que valem para além destes dois bugs:

- **Volume é um caso de teste.** Os dois só apareceram com 2.083 linhas e um ano
  de extrato; com 8 lançamentos digitados à mão, nenhum caía num dia 1º e nada
  produzia `transfer`. O roadmap já dizia "as telas foram vistas renderizadas" —
  falta dizer **com quanto dado**.
- **Um teste pode documentar um bug.** Os dois casos tinham teste verde: um
  evitando a fronteira, o outro afirmando o resultado errado. Teste verde prova
  que o código faz o que o teste diz, não que o teste diz a coisa certa.

### Concluído na fatia de detecção de poupança (branch `feat/deteccao-de-poupanca`)

A metade que faltava da RN-3.2: quem **cria** a linha não confirmada. O schema, o
contrato e a UI de confirmar já existiam desde a fatia de metas — o que não
existia era a ingestão produzindo o que eles esperavam.

| Item | Onde |
|---|---|
| `detectSavingsContribution` — a regra pura, com os motivos de recusa nomeados | `supabase/functions/_shared/ingest.ts` |
| 8 testes da regra, em `node --test` (sem Deno, sem Docker, sem rede) | `supabase/functions/_shared/ingest.test.ts` |
| `activeGoalsByAccount` — metas ativas do espaço, indexadas por conta, uma leitura por evento | `pluggy-sync-worker/index.ts` |
| `IngestedAccount.isSavingsTarget`, lido e **nunca escrito** pela ingestão | idem |
| `insertResilient` devolve `id` por `external_id` — é o que liga a contribuição ao lançamento | idem |
| `proposeSavings` — grava a contribuição pendente, `23505` contado em vez de engolido | idem |
| Contadores de poupança no `payload` do evento (propostos, semMeta, metaAmbigua, moedaDivergente) | idem |
| `GoalCopy.pending` + linha no card da meta | `.../savings/presentation/{goal_copy,goal_card}.dart` |
| 7 testes novos no app (4 do texto, 3 da tela) | `test/features/savings/{goal_copy,savings_page}_test.dart` |

**O sinal é unilateral: só a entrada na conta alvo.** Uma transferência entre
contas próprias chega em duas linhas — a saída na corrente e a entrada na
poupança —, e casar as duas exigiria heurística de valor-e-data que a questão #5
do PRD deixa aberta. A entrada basta, e não depende de a conta de origem estar
conectada. Custo: com só a corrente conectada, não há linha na conta alvo para
detectar, e nada é proposto.

**A regra pode ser generosa porque a proposta não move dinheiro.** Rendimento da
poupança também vira proposta, de propósito: a contribuição nasce
`confirmed=false`, e o falso-positivo custa um toque em "não", não progresso
errado. É o que dispensa acertar a heurística antes de ter dado real para
calibrá-la — e é a razão de `confirmed` ser do usuário e nunca do provedor.

**O que a regra se recusa a fazer é escolher meta.** Com duas metas ativas na
mesma conta a detecção devolve `metaAmbigua` e não propõe: confirmar move o valor
para a meta que a detecção apontou, e a UI não oferece trocá-la. Desempatar seria
adivinhar em nome do usuário.

**Só linha recém-inserida é proposta.** O caminho do UPDATE — reprocessamento —
nunca repropõe, e é isso que respeita o "não": recusar uma proposta é apagá-la, e
sem essa regra o mesmo extrato a traria de volta a cada sincronização. O preço
está anotado como débito: os **2.083 lançamentos ingeridos antes desta fatia
nunca são propostos**, e um backfill é ação à parte justamente porque reabre esse
"não".

**Dois contadores existiam e não eram renderizados.** `GoalProgress.pendingCount`
e `pendingContributionsCountProvider` foram escritos na fatia de metas "para a
tela já saber somar quando isso acontecer" — e nenhuma tela lia. Sem a linha no
card, a detecção gravaria dado que só apareceria para quem abrisse a meta certa
por conta própria. A linha usa superfície de poço, **nunca âmbar**: âmbar é
atenção de orçamento, e aqui não há nada errado, só algo a decidir.

⚠️ **Não foi exercitado rodando.** Typecheck (`deno check`), 29 testes de regra e
666 do app passam; o que nenhum deles prova é a ingestão gravando contribuição
contra a Pluggy real. Falta deployar a função e ver a proposta aparecer no app —
e o roadmap já registra duas vezes em que teste verde e dado certo não foram a
mesma coisa nesta mesma função.

O deploy é **passo do usuário** (`functions deploy` é bloqueado no agente):

```bash
supabase functions deploy pluggy-sync-worker --project-ref ivfcypfljxvwkvnvmuum
```

Nenhuma migration nova, e **sync rules não precisam ser republicadas**:
`savings_contributions` já é bucketizada por `space_id` com `select *`, e nenhuma
coluna foi adicionada.

### Concluído na fatia de streaks e badges (branch `feat/streaks-e-badges`)

Fase 1 fechada, menos a categorização por IA. **Zero migration** — ver o
[ADR 0009](adr/0009-conquista-derivada-ate-ser-anunciada.md).

| Item | Onde |
|---|---|
| `SavingsStreak` — sequência corrente, melhor marca e "em risco" | `.../savings/domain/savings_streak.dart` |
| `SavingsBadge` + `deriveBadges` — 7 conquistas, desbloqueadas primeiro | `.../savings/domain/savings_badge.dart` |
| `savingsStreakProvider` e `savingsBadgesProvider` | `.../savings/presentation/savings_providers.dart` |
| `StreakBanner` e `BadgesSection` na aba Poupança | `.../savings/presentation/{streak_banner,badges_section}.dart` |
| `StreakCopy` e `BadgeCopy` — o texto, testável sem widget | `.../savings/presentation/{streak_copy,badge_copy}.dart` |
| 55 testes novos (34 de domínio, 16 de texto, 5 de tela) | `test/features/savings/` |

**A semana corrente não quebra sequência, e essa é a regra que sustenta o
resto.** Contar a partir da semana corrente e exigir aporte nela zeraria a
sequência de qualquer pessoa na segunda-feira de manhã — o app anunciaria
fracasso por causa do calendário, não do comportamento. A contagem começa na
semana corrente **se** houver aporte nela, e na anterior caso contrário; só
semana **encerrada** sem aporte interrompe. `isAtRisk` existe para a tela dizer
"ainda há 3 dias" sem que o número caia.

**Nenhuma frase cobra, e há teste afirmando isso.** A RN-3.4 pede que a quebra
seja comunicada com tom de incentivo. Na prática isso proibiu três coisas: falar
em perda ("você perdeu sua sequência de 8 semanas" é factual e é exatamente o que
a regra veta — o que sobrou de 8 semanas virou marca pessoal), contagem
regressiva ameaçadora (a frase diz quantos dias **ainda há**), e zero em
destaque. Um teste varre todos os estados procurando "perde", "falhou",
"quebrou", "atras" — mesma forma do teste que já guardava `GoalCopy.status`.

**A conquista de meta conta só a por objetivo.** Meta mensal "conclui" todo mês
por desenho, e contá-la faria a conquista desbloquear em julho e sumir em 1º de
agosto. Num objetivo o acumulado só cresce, então o desbloqueio é estável.

**Os badges de sequência olham a melhor marca, não a corrente.** Quem fez 12
semanas e quebrou não perde a conquista — o que se perde é a sequência, não o
histórico dela.

**Um teste existente pegou um reuso errado.** O tile de conquista usava
`SavingsProgress` para a barra do que falta, e o teste "meta pausada não mostra
barra de progresso" passou a falhar — porque aquela barra **significa meta** no
sistema visual, e sete selos a repetiriam até gastar o sinal. Virou texto
("Faltam R$ 20,00"), que num tile de 148px informa mais que o traço. O teste
estava certo sobre uma coisa que eu não tinha pensado.

### O que falta na Fase 1

| Item | Estado |
|---|---|
| Open Finance — schema | ✅ Fundação pronta e na nuvem (fatia acima). |
| Open Finance — `pluggy-connect-token` | ✅ Deployada e **exercitada de verdade**: responde 200 contra a Pluggy real, e o widget aceita o token que ela emite. |
| Open Finance — `pluggy-webhook` e `pluggy-sync-worker` | ✅ Deployados, rodaram contra sandbox **e** conta real, e o reparo foi medido: **2.076** lançamentos, zero duplicata, `perdidas` = 0, fila vazia. |
| Open Finance — widget Connect | ✅ Internalizado, com 28 testes das partes puras, e **rodou num device**: o canal JS conversa, a allowlist não bloqueia o fluxo legítimo e o `SUCCESS` chega com `item_id`. |
| Open Finance — caminho no app | ✅ Percorrido de ponta a ponta no iPhone 17 Pro, com sandbox e com conta real, e o dado reparado está no Postgres. Falta **ver as 1.750 linhas no app** — a lista do mês, o resumo e o rótulo "Transferência" com dado de banco de verdade. |
| Open Finance — desconectar | ✅ Deployada e **exercitada rodando**: 3 conexões viraram 1, as contas do banco removido sobreviveram com o histórico órfão, e os nomes editados não foram sobrescritos. |
| Detecção/confirmação automática de contribuição | ✅ Escrita e testada (fatia acima): entrada em conta alvo com uma meta ativa vira contribuição `confirmed=false`, ligada ao lançamento importado. ⚠️ **Não exercitada rodando** — falta deployar o worker e ver a proposta chegar ao app |
| Streaks e badges básicos | ✅ Feitos e derivados, sem tabela (fatia acima e [ADR 0009](adr/0009-conquista-derivada-ate-ser-anunciada.md)): sequência semanal com melhor marca, e 7 conquistas. ⚠️ **Não vistos rodando** |
| Categorização por IA (premium) | ⏸️ **Adiada por decisão** (2026-07-28). Depende da questão #4 do PRD (modelo próprio vs. API, e como tratar dado sensível na inferência), que segue aberta. Fase 2 passou na frente |
| `recurring_challenge` como quarto tipo de meta | Fora de escopo por decisão (ver acima) |

---

## Fases 2 a 4 — não iniciadas

Nada de código. O que existe é **desenho**, não implementação.

| Fase | Escopo (PRD §14) | Estado |
|---|---|---|
| **2 — Colaboração** | Espaços `group` (split, saldos, liquidação Pix) e `household` (transparência total, contas vinculadas), convites, matriz de papéis | Schema de espaços e papéis **já pronto**. `Money.allocate()` já resolve a matemática do split (RN-2.1). Falta tudo de UI, `expense_splits`, `settlements`. |
| **3 — Social + gamificação** | `friendships`, feed, reações, desafios com ranking, push | Streak e conquistas já existem no app, derivados. Falta tudo do social. ⚠️ É aqui que `achievements` passa a ser necessária — não como cache, mas como registro de que a conquista **foi anunciada** ([ADR 0009](adr/0009-conquista-derivada-ate-ser-anunciada.md)). |
| **4 — Monetização + escala** | Paywall premium, relatórios com IA, widget | Nada. `profiles` não tem `subscription_tier`. |

---

## Débitos técnicos conhecidos

Ordenados por risco. Todos verificados no código.

### Resolvido

- [x] **O primeiro dia de todo mês estava invisível na visão mensal.**
      Comparação de texto entre formatos de data diferentes (`espaço` do
      PowerSync vs `T` do `toIso8601String`). Escondeu R$ 15.111,01 de despesa em
      julho/2026, e vivia desde a fatia de transações. **Lição transferível:** o
      teste que existia evitava a fronteira *e* criava a linha pelo próprio
      repositório — duas escolhas que, juntas, garantiam nunca reproduzir o caso
      real. Teste de recorte precisa do valor **de fronteira** e do dado no
      formato de quem realmente escreve.
- [x] **`transfer` contava como receita no resumo do mês.** `MonthSummary`
      somava em `income` tudo que não era saída. Inofensivo até a ingestão
      produzir `transfer`; aí a home mostrou R$ 10.641,79 de "Entradas" que eram
      pagamento de fatura. Havia um teste afirmando exatamente o comportamento
      errado.
- [x] **Remover conexão saiu do repository para a tela** — e ganhou o servidor
      que faltava. O débito dizia "falta decidir onde a ação mora"; mora numa
      folha, como todo gerenciamento deste app (conta, orçamento, categoria,
      meta). O que ele não previa é que o botão exigia uma **Edge Function nova**:
      sem revogar na Pluggy, "Remover banco" apagaria a linha e deixaria o
      consentimento valendo no banco, com a tela dizendo o contrário.
- [x] **Conta de Open Finance não é mais editável como qualquer outra.** Tipo e
      saldo (que a sincronização reescreve) aparecem como fato, com a data; nome,
      instituição, alvo de poupança e espaço vinculado seguem editáveis, porque a
      ingestão nunca os toca depois do INSERT. E "Excluir" desapareceu: a
      sincronização recriaria a conta e reimportaria o extrato inteiro.
- [x] **A Edge Function nunca falou com a Pluggy de verdade** (2026-07-28). As
      três falam: `pluggy-connect-token` emite token que o widget aceita, o
      webhook recebeu 6 eventos reais, e o worker buscou item, conta e transação.
      Foi essa passagem que produziu os dois bugs abaixo — o que confirma a
      lição que ela mesma tinha registrado: código que nunca rodou não é código
      que funciona.
- [x] **O fluxo de conectar banco nunca foi percorrido** (2026-07-28). Percorrido
      no iPhone 17 Pro com sandbox **e** com conta real: o canal JS conversa, a
      allowlist não bloqueia o fluxo legítimo, o salto para o OAuth volta e o
      `SUCCESS` chega com `item_id`.
- [x] **O widget Connect nunca rodou num device** (2026-07-28). Fechou junto com
      o item acima.
- [x] **A direção do lançamento importado estava errada em cartão — duas vezes.**
      A primeira regra veio da doc e gravou 27 compras de sandbox como receita; a
      segunda veio do sandbox e gravou **305 compras de conta real** como receita.
      A regra certa tem o **tipo de conta** dentro dela: em cartão o sinal é
      invertido (compra positiva, abatimento negativo), como a doc oficial de
      fato diz. **Lição transferível:** medir em um conector só não estabelece uma
      convenção, e a instrumentação que mede precisa gravar no **banco** —
      `console.log` de Edge Function não é legível por SQL nem pelo CLI.
- [x] **A ingestão perdia página inteira em silêncio — 1.433 lançamentos.** A
      causa é a **leitura de dedup**: um `in.()` com 433 ou 500 UUIDs monta URL de
      17 a 20 mil caracteres e o `fetch` de dentro da Edge Function não consegue
      enviá-la (`TypeError: error sending request`). O erro virava `return 0`, que
      significa "nada a fazer", e a página era descartada contando-se como
      escrita. Confere com o que sumiu: páginas de 433 e 500 falhavam, de 317 e
      299 passavam.

      Corrigido lendo em pedaços de 100 (`READ_CHUNK`), com o INSERT também em
      pedaços e recuo linha a linha, e com `perdidas` no diagnóstico — a soma que
      ninguém fazia era o que permitia "sucesso" com 1.433 linhas a menos.
      Reprocessado e medido: cartão de 317 para 1.750, `perdidas` = 0.

      **Lição transferível, e é sobre método:** de fora, um `in.()` com 500 UUIDs
      responde 200 — eu testei isso e descartei a hipótese certa. O teste tem de
      rodar de onde o código roda; de outro lugar, ele produz uma conclusão com a
      forma de evidência. Mesma família da lição do `UPSERT` de orçamento, um
      nível acima: não basta executar o SQL de verdade, é preciso executá-lo pelo
      mesmo caminho.
- [x] **As Edge Functions não tinham teste nenhum.** As decisões puras da
      ingestão moram em `_shared/ingest.ts`, com 16 testes que rodam em
      `node --test` — sem Deno, sem Docker e sem rede — e um gate no CI. Era o
      motivo pelo qual os dois bugs acima eram invisíveis: o único jeito de
      exercitar a regra era ingerir dado de verdade e conferir fatura à mão.
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

- [ ] **O histórico ingerido antes da detecção nunca é proposto.** A detecção de
      poupança só olha linha **recém-inserida**, para reprocessar não ressuscitar
      uma proposta que o usuário recusou. A consequência é que os 2.083
      lançamentos que já estavam no banco — inclusive qualquer transferência para
      conta alvo — não viram contribuição nenhuma. Um backfill resolveria de uma
      vez, e é ação deliberada e à parte por reabrir exatamente o "não" que a
      regra protege: teria de rodar uma vez só, sobre uma janela escolhida, e não
      a cada sincronização. Enquanto não existir, a detecção só se manifesta em
      extrato novo.

      **Decidido em 2026-07-28: não fazer por enquanto.** A detecção será
      exercitada com extrato novo mesmo. Fica registrado que "nada apareceu" é o
      sintoma esperado sobre dado antigo, não defeito da regra.
- [ ] **`pendingContributionsCount` continua sem tela.** O contador de pendentes
      do espaço inteiro é calculado e testado, e agora que a detecção existe o
      único lugar que anuncia pendência é o card da meta — dentro da aba
      Poupança. Quem não abrir a aba não fica sabendo. O caminho natural é um
      marcador na bottom nav, que é mudança de `AppShell` e não desta fatia.
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
- [ ] **O pagamento de fatura conta duas vezes, e só um lado foi resolvido.** No
      cartão ele agora é `transfer` (invisível no resumo, correto). Mas o outro
      lado do mesmo pagamento — o débito na conta corrente — continua chegando
      como `expense`, então o mês mostra o gasto das compras **e** o gasto de
      pagar a fatura. Resolver exige reconhecer o débito de fatura no extrato da
      corrente, o que depende de descrição ou da categoria da Pluggy: heurística,
      e é exatamente o tipo de regra que já envelheceu mal duas vezes aqui.
- [ ] **Estorno de cartão fica invisível no resumo.** Ele chega negativo, como
      pagamento de fatura, e vira `transfer` junto. Deveria abater despesa. Não
      há campo que os separe sem heurística de texto.
- [ ] **O cartão do sandbox mostra compra como transferência.** É o custo
      conhecido da regra ciente do tipo de conta: lá compra chega como `CREDIT`
      negativa, assinatura idêntica à de um pagamento de fatura. Se incomodar, o
      caminho é remover a conexão de sandbox — não mexer na regra, que está certa
      para conta real e tem teste dizendo isso.
- [ ] **O protocolo do widget Connect é contrato interno da Pluggy.** Os tipos de
      mensagem (`OAUTH_OPEN`, `LINK_OPEN`, `LOCATION`) e os nomes de evento na
      query (`SUCCESS`, `ERROR`, `CLOSE`, `LOGIN_SUCCESS`…) **não são
      documentados publicamente** — só se conhecem por leitura do fonte do
      pacote oficial. É a dívida que se aceitou ao internalizar o widget, e ela
      existiria igual usando o pacote deles (que também está parado). Se o fluxo
      parar sem nada nosso mudar, `pluggy_connect_event.dart` é o primeiro lugar
      a olhar.
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
| 5 | Detecção de poupança — falsos positivos | ✅ **Respondida por desenho, não por heurística**: o sinal é a **entrada numa conta alvo com uma meta ativa apontando para ela**, e a proposta nasce `confirmed=false`. A regra é generosa de propósito (rendimento também vira proposta) porque o falso-positivo custa um toque em "não", não progresso errado — o que dispensa calibrar heurística antes de ter dado real. O que a regra recusa é escolher entre duas metas na mesma conta. Falta exercitar rodando |
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
  o [0009](adr/0009-conquista-derivada-ate-ser-anunciada.md): streak e conquista
  são derivados do histórico, e `achievements` só passa a existir na Fase 3 —
  para registrar que a conquista **foi anunciada**, não para guardar o que se
  calcula
- **PRD**: `PRD.pdf` na raiz (git-ignored — 11,7 MB). É a fonte de *o quê* e
  *por quê*; este arquivo é o *onde estamos*
- [`docs/pluggy-api-reference.md`](pluggy-api-reference.md) — referência da API do
  agregador
- Design system visual: projeto `Finance App — Design System` no Claude Design.
  Os previews são HTML; o que sincroniza com o Dart é a **especificação**, não o
  código
