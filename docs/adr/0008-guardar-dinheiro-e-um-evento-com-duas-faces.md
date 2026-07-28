# ADR 0008 — Guardar dinheiro é um evento com duas faces

- Status: aceito
- Data: 2026-07-28

## Contexto

A fatia de metas de poupança entregou `savings_goals` e `savings_contributions`.
"Guardei um valor" gravava **uma** linha: a contribuição. O progresso da meta
andava, e nada mais no app se mexia — guardar R$ 500 não saía do saldo, não
entrava em `MonthSummary.outflow` e não aparecia na lista de lançamentos.

`TransactionType.savings` existia desde a fatia de transações, com a doc dizendo
"conta como saída porque o dinheiro deixa o saldo gastável mesmo sem ser
despesa". **Nada o produzia**: os dois segmentos da UI (registro rápido e
edição) têm duas posições e só emitem `expense`/`income`.

O roadmap descrevia o problema ao contrário — dizia que registrar um lançamento
`savings` não criava contribuição. Como lançamento `savings` não existia, o
buraco era o inverso.

## Decisão

**Guardar dinheiro é um evento com duas faces**, gravadas juntas:

- um **lançamento** `savings` — o dinheiro saiu do saldo gastável;
- uma **contribuição** — a meta andou.

As duas nascem na mesma `writeTransaction`, e o vínculo é
`savings_contributions.transaction_id` (migration `20260728000822`).

### Onde vive o vínculo

Na **contribuição**, não no lançamento. A contribuição é a face opcional: existe
lançamento sem meta em praticamente toda linha de `transactions`, a tabela mais
movimentada do app. Um `savings_goal_id` lá seria nulo em ~100% das linhas.

### Quem é o dono do evento

A **contribuição**. Consequências:

- `deleteContribution` leva o lançamento junto (o dinheiro não saiu).
- A folha de edição de lançamento **recusa** editar ou excluir um lançamento
  ligado a uma meta, e aponta para ela. Editar o valor de um lado faria a meta
  contar R$ 500 e o extrato mostrar R$ 300. O que trava é o **vínculo**, não o
  tipo: um `savings` sem contribuição segue editável.
- Excluir a **meta** apaga as contribuições e **deixa os lançamentos de pé**. O
  dinheiro saiu de verdade; quem desistiu foi a meta. Apagar o extrato porque
  alguém abandonou um objetivo reescreveria o passado financeiro.

### Forma do lançamento gerado

- `type = savings`, `amount_minor` positivo (a direção vem do tipo — ADR 0006).
- `category_id` **nulo**, de propósito: uma categoria faria o valor debitar um
  orçamento, e o usuário veria o limite de "Alimentação" andar porque guardou
  dinheiro.
- `description` = nome da meta. Sem ela, um lançamento sem categoria e sem
  descrição apareceria na lista como "Sem descrição".
- `account_id` = conta de **origem**, perguntada na folha ("Saiu de"). Não é a
  `linked_account_id` da meta, que é o destino.

## Consequências

- Guardar dinheiro passa a mexer no saldo do mês, nas saídas e na lista — que é
  o ponto.
- **A integridade local depende do cliente.** No Postgres o `on delete cascade`
  garante que apagar o lançamento apaga a contribuição; as tabelas locais do
  PowerSync são views e não cascateiam. Quem mantém as duas linhas juntas
  offline é a `writeTransaction` do repository, e SQL novo sobre `transactions`
  precisa lembrar disso.
- O SQL de `transactions` mora em `SavingsSql`, e não emprestado do
  `TransactionsRepository`, porque dois repositories não compartilham transação
  de escrita — e a atomicidade é o requisito.
- A ingestão da Pluggy (ADR 0005) ganha o encaixe que faltava: a contribuição
  detectada aponta para o lançamento importado. O vínculo é nulável justamente
  por isso, e o **tipo** do lançamento não é validado — a ingestão pode querer
  ligar uma `transfer` detectada para conta alvo de poupança.
- A home soma poupança dentro de "Saídas" sem distinguir. Está correto (o
  dinheiro saiu do saldo gastável), mas quando incomodar o caminho é "saídas,
  das quais R$ X guardados".

## Alternativas descartadas

- **Não ligar, só tornar legível.** Dizer na tela que contribuição não é
  lançamento. Zero migration, zero risco — e o usuário que guarda R$ 500 segue
  vendo o saldo do mês intacto. Documentaria a incoerência em vez de resolvê-la.
- **O lançamento como origem.** Registro rápido ganharia o tipo `savings` com
  seletor de meta. Exigiria quebrar o segmento de duas posições (ou inventar
  outro gesto), e o caminho "Guardei um valor" a partir da meta ficaria
  redundante — sendo que ele é o gesto natural quando se está olhando a meta.
- **Coluna `savings_goal_id` em `transactions`.** Nula em quase toda linha da
  tabela mais movimentada, e inverteria a propriedade do evento.
- **Derivar a contribuição do lançamento** (todo `savings` com conta alvo de
  poupança conta para a meta). É o que a RN-3.2 chama de detecção, desenhada
  para o Open Finance e não para lançamento manual — e depende de heurística que
  segue em aberto (questão #5 do PRD).
