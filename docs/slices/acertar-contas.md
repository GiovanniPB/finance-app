# Fatia: acertar-contas

tipo: feature

## Pronto quando

Acertar uma dívida do grupo zera o par.

> ⚠️ **Esta fatia carrega três entregas, e o método diz que são três fatias.**
> O "pronto quando" honesto seria "escolher quem pagou **e** ver quem deve a quem
> **e** poder acertar" — dois "e". A decomposição foi proposta
> (`pagador-explicito` ~700 linhas, depois `acertar-contas` ~1.500) e o usuário
> escolheu, em 2026-08-01, fazer tudo numa fatia aceitando o tamanho. O risco
> registrado: ~3.000 linhas e ~30 arquivos, o dobro do teto do `AGENTS.md`, com
> chance real de a fatia atravessar sessões. Se ela ficar aberta no meio, o
> estado está no repo — `git log` do branch e este contrato.

## Superfícies

- **`transaction_edit_sheet.dart`** ganha **"Quem pagou"** na seção de divisão:
  um seletor de membro, só em despesa de espaço `group`. Sem escolha explícita, o
  pagador é quem lançou.
- **`space_detail_page.dart`** ganha a seção **"Acertar contas"**, abaixo dos
  membros, só quando `space_type == group`. Nas outras situações a seção não
  existe, em vez de existir vazia — mesma regra do `split_section.dart`.
- **Registrar o acerto** é um diálogo de confirmação, **não** uma folha nova: é
  um sim/não sem campo nenhum, e folha custaria uma superfície do orçamento da
  fatia.

Nenhuma tela nova. Componente novo: `settlement_section.dart`.

Mockup: `docs/slices/acertar-contas.mockup.html` — **pendente de aprovação**
(o layout não começa antes)

> O mockup mora no repo, não na conversa. Se ele existe só no histórico da
> sessão, a próxima sessão perde o alvo visual e a fatia recomeça do zero.

## Decisões que esta fatia fecha

### Questão #2 do PRD — saldo líquido com algoritmo guloso

O saldo é **líquido por pessoa**, não par-a-par: soma-se o que cada um pagou,
subtrai-se o que cada um deve, e o resultado vira transferência casando o **maior
credor com o maior devedor** até tudo zerar. Isso produz no máximo `n−1`
transferências.

Não é o mínimo teórico — esse é NP-difícil (partição de subconjuntos) e não se
paga aqui. O preço aceito de propósito: o app pode mandar você pagar alguém com
quem você não gastou nada. É o mesmo incômodo do "simplify debts" do Splitwise, e
a saída, se doer, é oferecer a visão par-a-par como alternativa — não trocar o
algoritmo.

Vira ADR 0012 no fechamento, junto com a linha #2 saindo de "questões abertas"
em `product.md`.

### Quem pagou é coluna, não é quem lançou

A premissa "quem lança é quem pagou" foi **rejeitada pelo usuário**: na república
real alguém lança a despesa que outro pagou, e o saldo sairia errado. Entra
`transactions.paid_by`.

- **Nulo é legítimo** e significa "quem lançou". Um trigger no Postgres resolve
  para `coalesce(new.paid_by, new.created_by)`, e `Transaction.fromRow` faz o
  mesmo com a linha local — que não tem trigger e existe antes do round-trip.
- **`not null` com backfill foi descartado**: um cliente que enviasse nulo teria
  o batch recusado, e batch recusado é descartado em silêncio pelo
  `SupabaseConnector` (armadilha nº 4 deste repo). Nulo tolerado é o que mantém a
  falha impossível.
- **Sem validação de que o pagador é membro.** A tentação é um trigger com
  `private.is_space_member(space_id, paid_by)`; ele recusaria o batch quando o
  pagador saísse do espaço, e o sintoma seria a edição sumir no checkpoint. O
  seletor só oferece membro ativo; o banco não julga.
- **Escrito só no `update`.** `create` não ganha parâmetro: o seletor mora na
  folha de edição, e mexer na assinatura de `TransactionsRepository.create`
  custaria seis fakes de teste por nada.

### O acerto é um `transfer` dividido — sem tabela nova

"Carla me pagou R$ 150" grava um lançamento `type = 'transfer'` no grupo com
`paid_by = Carla` e **uma** parte de R$ 150 para mim. A mesma fórmula
`pagou − deve` absorve e zera o par.

Por que isto é melhor que uma tabela `settlements`:

- `transfer` já **não** entra em receita nem em despesa do resumo — pagar dívida
  não é gasto novo, e o gasto já foi contado quando a despesa entrou;
- tabela nova custou 2.455 linhas em `dividir-despesa` (migration, sync rules,
  schema local, entidade, repositório, fakes) e **exige republicar as sync rules
  à mão**. Coluna nova não exige;
- o acerto aparece na lista do mês, que é onde alguém vai procurar por ele.

O `SettlementRepository` escreve as duas linhas em SQL bruto na mesma
`writeTransaction` local — pelo mesmo argumento que faz `is_shared` e as partes
nascerem juntas.

### Só quem está na linha acerta

A ação aparece **apenas** nas transferências que envolvem quem está olhando:
"Já paguei" quando eu devo, "Já recebi" quando eu recebo. Transferência entre
outras duas pessoas é informativa.

Não é limitação técnica — é o que evita a pergunta "quem tem direito de declarar
pagamento alheio?", que não tem resposta boa sem confirmação do outro lado.

### Só entra despesa dividida

O saldo olha `type in ('expense', 'transfer')` **com partes gravadas**. Despesa de
grupo não dividida é gasto de quem lançou, não dívida de ninguém — contá-la
transformaria qualquer lançamento no espaço em cobrança silenciosa. `transfer`
sem partes continua fora: é pagamento de fatura, não acerto.

## Arquivos que mudam

Banco:

- `supabase/migrations/<ts>_pagador_explicito.sql` — coluna `paid_by`, índice,
  trigger de `coalesce`
- `packages/database/lib/src/schema.dart` — a coluna local
- `powersync/sync_rules.yaml` — **não muda**: `select *` já a carrega, e coluna
  nova não exige republicar. (A republicação pendente de `dividir-despesa`
  continua pendente, por causa da tabela `expense_splits`.)

Domínio:

- `apps/finance/lib/features/transactions/domain/transaction.dart` — `paidBy`,
  com o `coalesce` na fronteira
- `apps/finance/lib/features/transactions/domain/settlement.dart` *(novo)* —
  `MemberBalance`, `Transfer`, `minimalTransfers()`; Dart puro, sem Flutter
- `apps/finance/lib/features/transactions/domain/settlement_repository.dart`
  *(novo)* — interface própria, **não** método a mais em `TransactionsRepository`:
  seis fakes implementam aquela interface, e somar método lá custaria seis
  arquivos de churn

Dados:

- `apps/finance/lib/features/transactions/data/settlement_repository_impl.dart`
  *(novo)* — o SQL do saldo e a escrita do acerto
- `apps/finance/lib/features/transactions/data/transactions_repository_impl.dart`
  — `update` grava `paid_by`

Apresentação:

- `apps/finance/lib/features/transactions/presentation/transactions_providers.dart`
  — `settlementRepositoryProvider`, `settlementProvider(spaceId)`
- `apps/finance/lib/features/transactions/presentation/transaction_edit_controller.dart`
  — o pagador escolhido
- `apps/finance/lib/features/transactions/presentation/split_section.dart` —
  "Quem pagou" entra aqui, junto de "Dividido entre"
- `apps/finance/lib/features/spaces/presentation/settlement_section.dart` *(novo)*
- `apps/finance/lib/features/spaces/presentation/space_detail_page.dart` — monta
  a seção
- `apps/finance/lib/features/spaces/presentation/member_copy.dart` — rótulo
  **curto** para a linha de transferência. O fallback de hoje é "No espaço desde
  28 de julho", que numa transferência sairia como *"No espaço desde 28 de julho
  → Você"*. Fica **"Membro sem nome"** (escolha do usuário)
- `apps/finance/lib/di/providers.dart` — se o repositório novo precisar de
  registro no composition root

Testes:

- `apps/finance/test/features/transactions/settlement_test.dart` *(novo)*
- `apps/finance/test/features/transactions/settlement_repository_impl_test.dart`
  *(novo)*
- `apps/finance/test/features/spaces/settlement_section_test.dart` *(novo)*
- os testes existentes de `transaction`, `transactions_repository_impl`,
  `split_section`/`transaction_edit_sheet` e `member_copy`

No fechamento: `docs/state.md`, `docs/surfaces.md`, `docs/product.md`,
`docs/adr/0012-…`.

## Casos

Do algoritmo (`settlement_test.dart`, Dart puro):

- **vazio** — nenhuma despesa dividida: zero transferências
- **todos quites** — cada um pagou exatamente a própria parte: zero
  transferências, e a seção não fica listando três "R$ 0,00"
- **um deve, um recebe** — uma transferência
- **um pagou tudo, três pessoas** — duas transferências (`n−1`)
- **triângulo** — A deve a B, B deve a C, C deve a A, valores iguais: o guloso
  zera tudo sem transferência nenhuma
- **centavos** — R$ 0,01 entre três: as partes são 1, 0 e 0, e a soma das
  transferências fecha o saldo sem centavo evaporado
- **empate** — dois credores com o mesmo valor: ordem estável (desempate por
  `userId`), senão o teste passa por sorte da ordem do `Map`
- **a soma dos saldos é sempre zero** — invariante verificado antes de olhar as
  transferências; se não fecha, o erro está na leitura, não no rateio
- **moeda divergente** — recusa somar em vez de somar errado (invariante global
  de `product.md`)

Do repositório (`settlement_repository_impl_test.dart`, **SQL executado de
verdade** — armadilha nº 3: as tabelas locais são views com trigger
`INSTEAD OF`, e mock não distingue SQL válido de SQL recusado):

- despesa dividida entre três entra no saldo com o pagador de `paid_by`
- `paid_by` nulo cai em `created_by`
- despesa **não** dividida no mesmo espaço não entra
- `transfer` **sem** partes (pagamento de fatura) não entra
- lançamento de outro espaço não vaza para o saldo
- `income` não entra
- apagar o lançamento dividido devolve o saldo ao anterior
- membro que saiu (`status = 'left'`) com saldo continua aparecendo — sumir
  esconderia dívida
- **registrar o acerto zera o par**: depois de `settle`, o saldo dos dois vai a
  zero e o lançamento nasce `transfer` com uma parte só
- acertar duas vezes não zera duas vezes — o segundo acerto parte do saldo já
  zerado, então não há nada a registrar

Da seção (`settlement_section_test.dart`, widget):

- espaço `personal` e `household` não têm a seção
- grupo sem nada a acertar mostra "Está tudo quite", não uma lista de zeros
- grupo sem despesa dividida mostra o vazio que **diz onde dividir**
- a linha usa o nome do membro e cai em "Membro sem nome" quando não há nome
- quem está olhando aparece como "Você", em peso e cor de marca — não por fundo
  colorido: em grupo de três quase toda transferência envolve você, e destacar
  todas seria destacar nenhuma
- a transferência que **não** envolve você aparece igual, sem apagar: esconder
  metade faria as transferências não somarem com o saldo
- só a linha que envolve você tem ação
- membro que saiu ganha o qualificador "saiu do espaço"

Do seletor de pagador (`split_section` / `transaction_edit_sheet`):

- despesa de `group` oferece "Quem pagou"; `personal` e `household` não
- sem escolha, mostra quem lançou
- trocar o pagador e salvar preserva a divisão — o defeito gêmeo do `is_shared`
  que a fatia anterior encontrou no teste de integração

## Fora de escopo

- **Pix copia-e-cola.** O acerto é registrado, não cobrado: quem transfere é o
  usuário, no app do banco dele (`product.md`, "Não é"). Gerar a chave é fatia
  própria.
- **Confirmação do outro lado.** Quem registra o acerto decide sozinho. Um
  "aguardando Carla confirmar" precisa de estado de convite e notificação.
- **Visão par-a-par** como alternativa ao líquido — só se o incômodo aparecer no
  uso.
- **Acertar dívida de terceiros.** Ver a decisão acima.
- **Rateio percentual e exato.** Fatia própria, já listada em `state.md`.
- **Saldo do household.** O `household` liquida de outro jeito por desenho
  (PRD §4.2); tratá-lo aqui unificaria dois conceitos que o domínio separa de
  propósito.
- **Histórico de acertos como tela.** Eles aparecem na lista do mês como
  `transfer`, que é onde alguém procura.
