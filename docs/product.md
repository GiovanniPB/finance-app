# Finance — app de finanças pessoais colaborativo

> Destilado do PRD 1.0 (`PRD.pdf`, fora do repo por tamanho). Aqui fica o que
> muda decisão de código. Onde o PRD e este arquivo divergirem, **este vale** —
> a divergência é decisão tomada depois, e o ADR correspondente explica.

## Em uma frase

Um app onde a vida financeira **individual**, a **compartilhada** e o **hábito
de poupar** se retroalimentam — hoje três apps separados (Mobills, Splitwise,
Gym Rats) — para o mercado brasileiro, com Open Finance e Pix nativos.

A promessa de entrada que governa o desenho: **primeiro gasto registrado em
≤ 30 segundos**. Tudo o mais é revelação progressiva.

## Não é

- **Não é corretora nem banco.** Não move dinheiro. O Pix de liquidação é
  copia-e-cola: quem transfere é o usuário, no app do banco dele.
- **Não intermedeia aposta.** A prenda de desafio é **sempre simbólica e
  não-financeira** (texto livre do grupo). Isso mantém o produto fora do
  enquadramento de jogo/loteria — é regra regulatória, não estética.
- **Não expõe valor absoluto no social.** O feed comunica progresso relativo
  ("80% da meta", "4 semanas de sequência"), nunca montante, a menos que o
  usuário opte explicitamente.
- **Não é multi-moeda de verdade.** O schema carrega `currency`, a UI só oferece
  BRL, e agregado com moedas divergentes **se recusa a somar** em vez de somar
  errado.
- **Não faz orçamento envelope, previsão de fluxo de caixa nem investimentos.**

## Domínio

Duas naturezas, e a distinção decide mutabilidade e histórico:

- **modelo** — mutável, representa intenção do usuário (uma meta, um limite).
- **registro** — imutável em essência, representa algo que aconteceu (um
  lançamento, uma contribuição, um evento de webhook).

### Space (espaço)

- tipo: **modelo** · o conceito organizador de todo o produto
- pertence a: um `owner_id`; membros via `space_members`
- identidade: `id`, `space_type` ∈ `personal | household | group`
- invariantes:
  - todo usuário tem **exatamente um** `personal`, criado no signup, não
    removível
  - `household` e `group` são tipos **distintos**, não um "compartilhado
    genérico": privacidade, foco, liquidação e encerramento são opostos nos dois
    (PRD §4.2). Unificar geraria `if tipo == casal` espalhado
  - espaço não é apagado — vai para `status='archived'`, somente-leitura
    (RN-12.1). Histórico é preservado por integridade contábil
  - papel vem de `space_members.role` ∈ `admin | editor | viewer`; no `personal`
    o usuário é sempre `admin` e único membro

### Transaction (lançamento)

- tipo: **registro** (editável em campos de classificação, não em natureza)
- pertence a: um `space_id`; opcionalmente um `account_id`
- identidade: `id`, e `external_id` quando veio do Open Finance
- invariantes:
  - `amount_minor` é **inteiro positivo em centavos**; a direção mora em `type`
    ∈ `expense | income | transfer | savings` ([ADR 0006](adr/0006-politica-de-dinheiro.md))
  - `transfer` **não** entra em receita nem em despesa do resumo: pagar fatura é
    dinheiro trocando de bolso, e o gasto já foi contado quando a compra entrou
  - lançamento que pertence a uma meta **não é editável** pela folha comum — a
    contribuição é a dona do evento ([ADR 0008](adr/0008-guardar-dinheiro-e-um-evento-com-duas-faces.md))
  - `description` é do usuário depois do INSERT: a sincronização nunca a
    sobrescreve
  - a direção de lançamento importado depende do **tipo de conta** — em cartão a
    convenção de sinal é invertida. A regra e a tabela-verdade medida vivem em
    `supabase/functions/_shared/ingest.ts`; ela já foi trocada duas vezes e as
    duas gravaram dinheiro errado

### Account (conta)

- tipo: **modelo** com um campo de registro: o saldo é **snapshot informado**,
  com `balance_as_of` dizendo de quando
- invariantes:
  - saldo **não** reconcilia com lançamento, por decisão. A tela diz a data do
    número em vez de fingir que ele é atual
  - só o **dono** (`accounts.user_id`) vincula ou desvincula a conta de um
    espaço, independente do papel dele lá — soberania sobre dado financeiro
    próprio (PRD §7)
  - desconectar o banco preserva os lançamentos: eles ficam com `account_id`
    nulo, não somem

### Category (categoria)

- tipo: **modelo** · `space_id` nulo significa categoria global do sistema
- invariantes: `color` é **índice de paleta**, não hex; categoria em uso não
  pode ser removida (a UI diz quantos lançamentos a usam)

### Budget (orçamento)

- tipo: **modelo** · limite por categoria e período, com vigência por `starts_at`
- invariantes: vale o mais recente vigente no mês em foco; a comparação é
  **mês a mês**, nunca `DateTime` cru (fuso muda o mês)

### SavingsGoal (meta) e SavingsContribution (contribuição)

- meta: **modelo** · `goal_type` ∈ `objective | fixed_amount | percentage_income`
- contribuição: **registro** · é a dona do evento de guardar dinheiro
- invariantes:
  - `current_amount` é **derivado** da soma das contribuições confirmadas, nunca
    coluna mantida à mão ([ADR 0007](adr/0007-agregado-derivado-vs-coluna.md))
  - guardar dinheiro grava **duas linhas na mesma transação**: a contribuição e
    um lançamento `savings` ligado a ela ([ADR 0008](adr/0008-guardar-dinheiro-e-um-evento-com-duas-faces.md))
  - contribuição detectada pelo Open Finance nasce `confirmed=false` e **não
    move o progresso** até o usuário confirmar
  - a base de `percentage_income` é a soma dos `income` do mês em foco, e a tela
    mostra de onde o número saiu — nada é declarado à parte para não envelhecer
    calado
  - `recurring_challenge` como quarto tipo está **fora de escopo** por decisão

### Streak e Achievement (sequência e conquista)

- tipo: **derivados** — não existem como tabela
  ([ADR 0009](adr/0009-conquista-derivada-ate-ser-anunciada.md))
- invariante: `achievements` só nasce na Fase 3, e para registrar que a conquista
  **foi anunciada** — não para guardar o que se calcula

## Invariantes globais

- **Todo valor monetário é inteiro em unidades mínimas.** Nunca `double`
  ([ADR 0006](adr/0006-politica-de-dinheiro.md)).
- **Toda linha tem `owner_id` e RLS obrigatória.** Autorização é por
  membership de espaço ([ADR 0004](adr/0004-multi-tenancy-por-espacos.md)).
- **Policy diz *quais linhas*; trigger diz *quais colunas e transições*.** Não
  existe `OLD` numa policy. Foi assim que qualquer editor podia se promover a
  admin — a medição está no cabeçalho de `20260728210321_papeis_de_membro.sql`.
- **A policy de SELECT governa a linha velha e a linha nova de todo UPDATE**, e
  a linha nova de todo INSERT. Linha invisível ⇒ ou `42501`, ou **0 linhas em
  silêncio**. Cabeçalho de `20260728204229`.
- **Agregado é derivado; coluna é só para fato informado**
  ([ADR 0007](adr/0007-agregado-derivado-vs-coluna.md)).
- **Offline-first.** O app funciona sem rede; PowerSync sincroniza e o Postgres
  arbitra via RLS. O que o servidor recusa é descartado — silenciosamente, o que
  torna a RLS errada indistinguível de "não salvou".
- **Tempo é o do dispositivo**, e o mês vai do primeiro instante do dia 1º ao
  último do último dia. Não há fechamento de período.
- **Erro nunca vaza como exception para a UI**: vira `Result<T, Failure>` na
  fronteira da camada `data`.

## Fluxos principais

1. **Registrar gasto** — `+` → valor, categoria, conta → salvo, offline
   inclusive. É o fluxo dos 30 segundos.
2. **Ver o mês** — home mostra saldo gastável, entradas, saídas e orçamento com
   alerta em 80% e 100%.
3. **Conectar banco** — widget da Pluggy → consentimento → o worker ingere
   contas e extrato server-side ([ADR 0005](adr/0005-open-finance-pluggy-server-side.md)).
4. **Guardar dinheiro** — meta → "guardei R$ X" → contribuição + lançamento
   `savings` nascem juntos → progresso e sequência se movem.
5. **Confirmar aporte detectado** — entrada em conta alvo com meta ativa vira
   proposta `confirmed=false` → o sim do usuário move o progresso.
6. **Compartilhar espaço** — criar `household`/`group` → convidar por código →
   entrar → gerir papéis, remover, sair, arquivar.
7. **Dividir despesa** *(Fase 2, não implementado)* — marcar "dividir" →
   `expense_splits` → saldo "quem deve a quem" → liquidar via Pix.

## Decisões

Ver [`docs/adr/`](adr). As caras de reverter moram lá, não aqui.

## Questões de produto ainda abertas

Do PRD §15, o que segue sem decisão e **bloqueia** trabalho:

| # | Questão | Bloqueia |
|---|---|---|
| 2 | Algoritmo de minimização de transferências (RN-2.2) | saldo "quem deve a quem" |
| 4 | IA de categorização: modelo próprio vs. API, e dado sensível na inferência | categorização por IA |
| 6 | Limite de contas Open Finance no plano grátis (1 ou 2) | paywall |
| 7 | Household com 3+ pessoas — o schema suporta, a UX de "casal" pressupõe 2 | nada hoje |
| 8–10 | Moderação de feed, cadência de notificação, gamificação vs. saúde financeira | Fase 3 |

Respondidas e já refletidas acima: regime de renda (#1), provedor de Open
Finance (#3, [ADR 0005](adr/0005-open-finance-pluggy-server-side.md)) e falso
positivo de detecção (#5, resolvido por desenho — a proposta custa um toque em
"não", não progresso errado).
