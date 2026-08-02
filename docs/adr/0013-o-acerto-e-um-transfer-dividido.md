# 0013 — O acerto é um `transfer` dividido, não uma tabela

## Contexto

Ver o saldo sem poder dizer "já paguei" é pior do que não ver: no segundo mês a
tela cobra uma dívida que já foi paga por Pix. Registrar o acerto era, então,
requisito da mesma fatia.

O desenho óbvio é uma tabela `settlements` — `from`, `to`, `amount`, `space_id`,
data. É o que qualquer modelagem de domínio produziria, e é caro neste projeto
de um jeito específico: a fatia anterior mediu que **uma tabela nova custa ~2.455
linhas** (migration, sync rules, schema local, entidade, três métodos de
repositório, seis fakes) e, pior, **exige republicar as sync rules à mão no
dashboard** — a armadilha nº 1 do repo, que falha como tela vazia sem erro
nenhum.

Ao mesmo tempo, o saldo já é `pagou − deve` sobre `transactions` e
`expense_splits`, e `paid_by` acabara de nascer nesta mesma fatia.

## Decisão

"Carla me pagou R$ 150" grava **um lançamento `type = 'transfer'`** no espaço,
com `paid_by = Carla` e **uma** parte de R$ 150 para mim, na mesma
`writeTransaction` local.

A fórmula do saldo absorve as duas linhas sem lógica especial: Carla ganha +150
no "pagou", eu ganho +150 no "deve", e o par zera. Nenhum código sabe o que é um
"acerto" — ele é uma despesa dividida entre uma pessoa só.

A ação existe apenas nas transferências que envolvem quem está olhando.

## Alternativas descartadas

- **Tabela `settlements`** — ver o contexto. O custo é conhecido e medido, e o
  que ela compraria (um tipo próprio, com data e histórico separados) já existe
  na lista do mês.
- **Coluna `is_settlement` em `transactions`** — barata, mas seria um campo cuja
  única função é dizer o que o dado já diz. `transfer` com partes **é** o acerto.
- **Marcar as partes como pagas** (`expense_splits.settled_at`) — quebraria o
  invariante de que a soma das partes fecha o total do lançamento, e obrigaria o
  acerto parcial a fatiar partes existentes.
- **Deixar o usuário registrar o acerto à mão**, como um lançamento comum — é o
  que acontece hoje sem esta fatia, e não zera nada: sem `paid_by` e sem parte,
  o saldo não muda.

## Consequência

Fica fácil: zero migration, zero republicação de sync rules, zero fake novo em
`TransactionsRepository`. O acerto aparece na **lista do mês** como
transferência, que é onde alguém procura por ele — e `transfer` já não conta em
receita nem em despesa do resumo, então registrar um acerto não mexe no gasto do
mês.

Fica difícil: **acerto e pagamento de fatura passam a ser o mesmo tipo.** O que
os separa é ter partes — o pagamento de fatura vindo do Open Finance nunca tem.
A distinção é real mas é implícita, e o SQL do saldo carrega essa condição em
duas cláusulas (`_hasSplits`). Se um dia a ingestão passar a criar `transfer`
com partes, o saldo começa a contar dinheiro que não é dívida, e o sintoma será
um saldo que não fecha.

O acerto **parcial** não existe: o valor é o da transferência proposta, inteiro.
Pagar metade exigiria uma tela de valor, e ela não estava nesta fatia.

Ninguém confirma do outro lado. Quem registra decide sozinho que o dinheiro
mudou de mãos, e o outro vê o saldo zerar sem ter dito nada. É aceitável entre
pessoas que já dividem despesas, e o conserto — se doer — é estado de
confirmação, não outra modelagem do acerto.
