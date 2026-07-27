-- =========================================================================
-- accounts: os campos que faltavam para a conta ser uma conta.
--
-- A tabela nasceu com o mínimo (nome + moeda) porque a Fase 0 registra gasto
-- sem perguntar de onde saiu. A Fase 1 (poupança + Open Finance) gira em torno
-- de conta: meta precisa saber para onde o dinheiro vai, e ingestão da Pluggy
-- precisa de onde encaixar instituição, tipo e saldo. Completar agora evita
-- mexer duas vezes no mesmo lugar.
--
-- Três convenções desta migration valem registro:
--
--  1. `current_balance_minor` é sempre POSITIVO; a direção vem de
--     `account_type`, exatamente como `amount_minor` tira a direção de `type`
--     em `transactions`. Para `credit_card` o valor é a FATURA (o que se deve),
--     que é também como a Pluggy entrega (`balance` em valor absoluto, e para
--     cartão representa o valor da fatura — ver docs/pluggy-api-reference.md
--     §7.3). O Dart aplica o sinal na fronteira, em `Account.signedBalance`.
--
--  2. `account_type` usa os nomes do nosso domínio, não os da Pluggy, mas o
--     conjunto foi escolhido para o mapeamento ser total:
--     CHECKING_ACCOUNT→checking, SAVINGS_ACCOUNT→savings,
--     CREDIT_CARD→credit_card. `investment`, `cash` e `other` cobrem o que
--     entra na mão. Um `text` com check em vez de enum do Postgres: o
--     PowerSync materializa enum como texto de qualquer forma, e crescer um
--     check é mais barato que `alter type`.
--
--  3. Saldo é SNAPSHOT, não soma de lançamento. É "o que o banco dizia da
--     última vez", digitado pelo usuário hoje e sobrescrito pela ingestão da
--     Pluggy na Fase 1 (coluna de propriedade do provedor, ver ADR 0005). Não
--     é derivado de `transactions` de propósito: lançamento manual cobre uma
--     fração do extrato, então derivar daria um número errado com cara de
--     certo.
-- =========================================================================

alter table public.accounts
  add column account_type text not null default 'checking'
    check (
      account_type in (
        'checking', 'savings', 'credit_card', 'investment', 'cash', 'other'
      )
    ),
  add column institution text
    check (institution is null or char_length(institution) between 1 and 120),
  add column current_balance_minor bigint not null default 0
    check (current_balance_minor >= 0),
  add column is_savings_target boolean not null default false;

-- Metas de poupança (Fase 1) perguntam "quais contas contam como poupança?".
-- Índice parcial: a resposta é sempre um subconjunto pequeno.
create index accounts_savings_target_idx
  on public.accounts (owner_id)
  where is_savings_target;

-- `replica identity full` já vale desde 20260714153330 e sobrevive a
-- `add column`; a publication é `for all tables`. Nada a fazer nos dois.
