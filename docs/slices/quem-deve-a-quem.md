# Fatia: quem-deve-a-quem

tipo: feature

## Pronto quando

Abrir um espaço `group` mostra a menor lista de transferências que zera a conta
de todo mundo.

## Superfícies

`space_detail_page.dart` ganha a seção **"Acertar contas"**, logo abaixo dos
membros. Ela aparece **só** quando `space_type == group`; nas outras situações a
seção não existe, em vez de existir vazia — mesma regra do `split_section.dart`.

Nenhuma tela nova. Um componente novo: `settlement_section.dart`.

Mockup: `docs/slices/quem-deve-a-quem.mockup.html` — **pendente de aprovação**
(o código não começa antes)

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

### Quem pagou é quem lançou

Não existe coluna `paid_by`: o pagador é `transactions.created_by`. Criar a
coluna seria migration + republicar sync rules + tela para escolher o pagador —
uma fatia inteira, e esta não tem tabela nova de propósito (a anterior custou
2.455 linhas justamente por ter uma).

Se a premissa doer no uso — alguém lança a despesa que outro pagou —, o conserto
é a fatia `pagador-explicito`, não um remendo aqui.

### Só entra despesa dividida

O saldo olha `type = 'expense'` com `is_shared` e partes gravadas. Despesa de
grupo **não** dividida é gasto de quem lançou, não dívida de ninguém — contá-la
transformaria qualquer lançamento no espaço em cobrança silenciosa.

## Arquivos que mudam

Nascem:

- `apps/finance/lib/features/transactions/domain/settlement.dart` —
  `MemberBalance`, `Transfer` e `minimalTransfers()` (Dart puro, sem Flutter)
- `apps/finance/lib/features/transactions/domain/settlement_repository.dart` —
  interface própria, **não** um método a mais em `TransactionsRepository`: seis
  fakes de teste implementam aquela interface, e somar método lá custaria seis
  arquivos de churn por nada
- `apps/finance/lib/features/transactions/data/settlement_repository_impl.dart`
- `apps/finance/lib/features/spaces/presentation/settlement_section.dart`
- `apps/finance/test/features/transactions/settlement_test.dart`
- `apps/finance/test/features/transactions/settlement_repository_impl_test.dart`
- `apps/finance/test/features/spaces/settlement_section_test.dart`

Mudam:

- `apps/finance/lib/features/transactions/presentation/transactions_providers.dart`
  — `settlementRepositoryProvider` + `settlementProvider(spaceId)`
- `apps/finance/lib/features/spaces/presentation/space_detail_page.dart` — monta
  a seção
- `apps/finance/lib/features/spaces/presentation/member_copy.dart` — rótulo
  **curto** para a linha de transferência. O fallback de hoje é "No espaço desde
  28 de julho", que numa transferência sai como *"No espaço desde 28 de julho →
  Você"*; o mockup propõe "Membro sem nome"
- `apps/finance/test/features/spaces/member_copy_test.dart` — o rótulo curto
- `apps/finance/lib/di/providers.dart` — se o repositório novo precisar de
  registro no composition root
- `docs/state.md`, `docs/surfaces.md`, `docs/product.md`, `docs/adr/0012-…` — no
  fechamento

Nada em `supabase/`, nada em `powersync/`, nada em `schema.dart`: **esta fatia
não tem migration**. Se aparecer uma, o escopo vazou.

## Casos

Do algoritmo (`settlement_test.dart`, Dart puro):

- **vazio** — nenhuma despesa dividida: zero transferências
- **todos quites** — cada um pagou exatamente a própria parte: zero
  transferências, e a seção não fica dizendo "R$ 0,00" para três pessoas
- **um deve, um recebe** — uma transferência
- **um pagou tudo, três pessoas** — duas transferências (`n−1`)
- **triângulo** — A deve a B, B deve a C, C deve a A, valores iguais: o guloso
  zera tudo sem transferência nenhuma
- **centavos** — R$ 0,01 entre três: as partes são 1, 0 e 0, e a soma das
  transferências fecha o saldo sem centavo evaporado
- **empate** — dois credores com o mesmo valor: a ordem é estável (desempate por
  `userId`), senão o teste passa por sorte
- **moeda divergente** — se houver mais de uma moeda no espaço, recusa somar em
  vez de somar errado (invariante global de `product.md`)

Do repositório (`settlement_repository_impl_test.dart`, **SQL executado de
verdade** — armadilha nº 3: as tabelas locais são views com trigger
`INSTEAD OF`, e mock não distingue SQL válido de SQL recusado):

- despesa dividida entre três entra no saldo com o pagador certo
- despesa **não** dividida no mesmo espaço não entra
- lançamento de outro espaço não vaza para o saldo
- `income` e `transfer` não entram
- apagar o lançamento dividido devolve o saldo ao anterior
- membro que saiu (`status = 'left'`) com saldo continua aparecendo — sumir
  esconderia dívida

Da seção (`settlement_section_test.dart`, widget):

- espaço `personal` e `household` não têm a seção
- grupo sem nada a acertar mostra o estado vazio, não uma lista de zeros
- a linha usa o **nome** do membro e cai no rótulo curto quando não há nome
- quem está olhando aparece como "Você", em peso e cor de marca — não por fundo
  colorido: em grupo de três quase toda transferência envolve você, e destacar
  todas seria destacar nenhuma
- a transferência que **não** envolve você aparece igual, sem apagar: esconder
  metade faria as transferências não somarem com o saldo
- membro que saiu ganha o qualificador "saiu do espaço"

## Fora de escopo

- **Liquidar.** Não há como dizer "já paguei". O saldo é cumulativo desde sempre
  e nada o zera — quem pagar por Pix vai continuar vendo a dívida. É a fatia
  seguinte (`liquidar-acerto`: registrar o acerto como lançamento, o que zera o
  par), e é ela que torna esta útil no segundo mês.
- **Pix copia-e-cola.** Depende de liquidar existir primeiro.
- **Visão par-a-par** como alternativa ao líquido — só se o incômodo aparecer no
  uso.
- **Rateio percentual e exato.** Fatia própria, já listada em `state.md`.
- **Coluna `paid_by`.** Ver a decisão acima.
- **Saldo do household.** O `household` tem liquidação diferente do `group` por
  desenho (PRD §4.2); tratá-lo aqui seria unificar dois conceitos que o domínio
  separa de propósito.
