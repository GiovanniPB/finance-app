# 0012 — O saldo do grupo é líquido, e o guloso basta

## Contexto

A questão #2 do PRD (RN-2.2) bloqueava "quem deve a quem" desde a fundação:
como o saldo de um grupo vira transferências. Há duas perguntas embutidas, e
elas foram confundidas o tempo todo.

A primeira é **de produto**: o saldo é par-a-par (cada despesa gera dívida de
cada membro para quem pagou, somada por par) ou **líquido** (o que cada um pagou
menos o que deve, e o resto é aritmética)? Par-a-par é rastreável — "você deve à
Ana porque ela pagou o mercado" — e nunca cancela o triângulo A→B→C→A, que numa
república de três acontece toda semana.

A segunda é **de algoritmo**: dado o saldo líquido, qual o menor número de
transferências que o zera? Essa pergunta tem resposta conhecida e ruim: é
NP-difícil, por redução da partição de subconjuntos. Achar o mínimo verdadeiro
exige procurar todo subgrupo que já se cancela entre si.

## Decisão

**Líquido, com casamento guloso.** Soma-se por pessoa `pagou − deve`; o maior
credor é casado com o maior devedor, repetidamente, até tudo zerar. Cada passo
zera ao menos uma das duas pontas, então a saída tem no máximo `n−1`
transferências para `n` pessoas.

Empate de valor é desempatado por `userId`. Sem isso a saída dependeria da ordem
em que o SQL devolveu as linhas — e um teste que passa por essa ordem passa por
sorte.

Só entra no saldo lançamento **com partes gravadas**. Despesa de grupo não
dividida é gasto de quem lançou, não dívida de ninguém.

## Alternativas descartadas

- **Par-a-par, sem simplificar** — mais rastreável, e é o que alguém desenharia
  primeiro. Não cancela o triângulo: três pessoas que se revezam pagando o
  mercado acumulariam seis dívidas cruzadas que somam zero. Continua sendo a
  saída se o incômodo do líquido aparecer no uso, e é a razão de o saldo por
  pessoa ficar guardado em `Settlement.balances` em vez de só as transferências.
- **O mínimo verdadeiro** — NP-difícil. Para os grupos deste produto (3 a 6
  pessoas) rodaria rápido, mas seria código exponencial mantido para ganhar
  raramente uma transferência a menos.
- **Adiar de novo** — a questão bloqueava a Fase 2 inteira desde a fundação.

## Consequência

Fica fácil: o saldo é uma soma e o algoritmo cabe em 30 linhas de Dart puro,
sem banco. A soma dos saldos é sempre zero, o que dá um invariante barato de
verificar — e é o `assert` que separa "erro na leitura do banco" de "erro no
rateio".

Fica difícil: **o app pode mandar você pagar alguém com quem não gastou nada.**
Bruno deve à Ana, a Ana deve a você, e o guloso manda Bruno te pagar direto.
Está aritmeticamente certo e é o mesmo incômodo do "simplify debts" do
Splitwise, que gera reclamação recorrente lá. O custo é aceito de propósito: a
saída, se doer, é oferecer a visão par-a-par **ao lado** da líquida, não trocar
o algoritmo.

O triângulo desaparece antes de qualquer tela, o que tem um efeito colateral no
teste: quando os saldos chegam ao algoritmo ele já virou três zeros,
indistinguível de "todo mundo quite". O caso só se prova onde a soma acontece,
no SQL — e por isso o teste dele mora em
`settlement_repository_impl_test.dart`, não no do domínio.
