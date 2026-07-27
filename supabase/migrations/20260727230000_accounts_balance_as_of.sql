-- =========================================================================
-- accounts.balance_as_of: desde quando o saldo é verdade.
--
-- O saldo é um snapshot digitado pelo usuário (ver o cabeçalho da migration
-- 20260727210000). Registrar gasto **não** o move, por decisão: derivar saldo
-- de lançamento manual daria um número errado com cara de certo. O risco desse
-- desenho é o número envelhecer calado — "R$ 2.500,00" não diz se é de hoje ou
-- de março.
--
-- `updated_at` não serve para isso: renomear a conta já o renova, e a tela
-- passaria a afirmar que o saldo é de hoje sem ninguém ter conferido saldo
-- nenhum. Daí uma coluna própria, que só se move quando o **valor** muda.
--
-- Na Fase 1 a ingestão da Pluggy passa a escrever esta coluna junto com o
-- saldo, e aí ela responde "quando o banco falou pela última vez" — a mesma
-- pergunta, com uma fonte melhor.
-- =========================================================================

alter table public.accounts
  add column balance_as_of timestamptz not null default now();
