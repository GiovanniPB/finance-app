# ADR 0007 — Agregado é derivado, não coluna

- Status: aceito
- Data: 2026-07-27

## Contexto

O PRD modela dois campos que são, por definição, somas de outras linhas:

- `savings_goals.current_amount` — a RN-3.3 o define como "a soma das
  contribuições confirmadas";
- `accounts.current_balance` — que **não** é agregado (é snapshot informado pelo
  usuário, ver a migration `20260727210000`), mas parece um.

O app é **offline-first**: dois aparelhos do mesmo usuário escrevem sem se ver e
o PowerSync resolve depois, por linha, com last-write-wins.

Uma coluna que precisa ser igual a uma soma tem um problema estrutural nesse
regime. Se o aparelho A adiciona uma contribuição de R$ 100 e o aparelho B outra
de R$ 50, ambos offline, cada um também atualiza `current_amount` a partir do
valor que **ele** conhecia. Sobem duas linhas de contribuição (as duas
sobrevivem, são linhas distintas) e dois valores de `current_amount`. O último
upload ganha, e o total fica errado — sem erro, sem conflito visível, e com cara
de dado válido.

## Decisão

**Nenhum agregado é persistido. Agregado é derivado na leitura.**

Concretamente:

- `savings_goals` **não tem** `current_amount`. `GoalProgress` compõe meta +
  contribuições e calcula acumulado, razão, restante e ritmo.
- `budgets` não tem `spent`. `BudgetUsage` compõe orçamento + transações do mês.
- `MonthSummary` deriva entradas, saídas e saldo das transações do mês.

A regra de agregação vive no **domínio** (não na apresentação, não em SQL), pelo
mesmo motivo nos três casos: o que conta como saída, o que conta como
contribuição confirmada e qual é a janela do período são regra de negócio, e no
domínio elas são testáveis sem Riverpod e sem banco.

A agregação acontece em **Dart**, e não como `SUM()` no SQL, porque as janelas
são pequenas — um mês de transações, as contribuições de uma meta: dezenas a
centenas de linhas. Se uma janela crescer para anos, aquele caso específico vira
query agregada; a decisão de não persistir o resultado continua valendo.

### Quando um número *pode* ser coluna

Quando ele é um **fato informado**, não uma soma. `accounts.current_balance_minor`
é coluna legítima: é "o que o banco dizia da última vez", digitado pelo usuário
ou escrito pela ingestão da Pluggy. Ninguém pode recalculá-lo a partir de outras
linhas — derivá-lo de `transactions` daria um número errado com cara de certo,
porque lançamento manual cobre uma fração do extrato.

O teste é: **se duas réplicas offline podem chegar a valores diferentes para a
mesma verdade, não é coluna.**

## Consequências

- Toda tela que mostra progresso lê duas coleções em vez de uma. Na prática isso
  é um `watch` a mais, e o custo real é nenhum na escala de um espaço pessoal.
- Não existe estado inconsistente possível entre o acumulado e as linhas que o
  compõem: o acumulado não existe até ser calculado.
- Um agregado novo não pede migration. `pendingCount` e `lifetimeContributed`
  nasceram depois do schema, sem tocar no banco.
- **Contrapartida real:** consulta agregada no servidor (relatório da Fase 4,
  feed da Fase 3) não tem uma coluna pronta para ler. Quando isso doer, o caminho
  é uma **view** ou uma tabela de leitura derivada por trigger no Postgres — onde
  há uma única fonte de escrita e o problema de réplica não existe —, nunca uma
  coluna que o cliente offline mantenha.

## Alternativas descartadas

- **Coluna mantida pelo cliente**: é o cenário do contexto. Desincroniza em
  silêncio.
- **Coluna mantida por trigger no Postgres**: consistente no servidor, mas o
  cliente offline mostraria o valor velho até o sync voltar — e o número que o
  usuário acabou de mover é justamente o que ele está olhando. Além disso, o
  PowerSync teria de propagar a linha da meta a cada contribuição, dobrando o
  tráfego de sync para um dado que o cliente já sabe calcular.
- **`SUM()` no SQL a cada leitura**: resolveria a consistência, mas jogaria a
  regra de negócio (o que conta como confirmado, qual é a janela do tipo de meta)
  para dentro de strings de SQL, fora do alcance de teste de domínio.
