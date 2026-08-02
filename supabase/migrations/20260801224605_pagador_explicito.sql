-- =========================================================================
-- acertar-contas: quem pagou a despesa deixa de ser quem a lançou.
--
-- POR QUE A COLUNA EXISTE. O saldo "quem deve a quem" é `pagou − deve`, e até
-- aqui "pagou" só podia ser `created_by`. Na república real quem registra o
-- mercado não é sempre quem passou o cartão — e o saldo sairia errado, em
-- dinheiro, sem nenhum sinal de que estava errado. A premissa foi rejeitada por
-- decisão de produto de 2026-08-01 (ver `docs/slices/acertar-contas.md`).
--
-- POR QUE NULLABLE, E NÃO `not null` COM BACKFILL.
--
-- `not null` é a modelagem que parece mais correta e é a que quebra o app. O
-- cliente é offline-first: a escrita chega pela fila de upload do PowerSync, e
-- um batch recusado pelo Postgres o `SupabaseConnector` **descarta em
-- silêncio** — a linha aparece aplicada no aparelho e some no checkpoint
-- seguinte. É a armadilha nº 4 deste repo, e ela já mordeu aqui. Qualquer
-- caminho que envie `paid_by` nulo (versão antiga do app, INSERT que não conhece
-- a coluna, ingestão do Open Finance) viraria perda de dado sem erro.
--
-- Nulo tolerado torna essa falha impossível: **nulo significa "quem lançou"**. O
-- trigger abaixo resolve para `created_by` na entrada, e `Transaction.fromRow`
-- faz o mesmo `coalesce` na linha local — que não tem trigger e existe antes do
-- round-trip. As 2.083 linhas que já estão no banco continuam certas sem UPDATE
-- nenhum.
--
-- POR QUE NÃO HÁ VALIDAÇÃO DE QUE O PAGADOR É MEMBRO DO ESPAÇO.
--
-- A tentação é um `check` com `private.is_space_member(space_id, paid_by)`. Ele
-- recusaria o batch no dia em que o pagador saísse do espaço — e pelo parágrafo
-- acima, batch recusado é dado perdido em silêncio, não erro na tela. Pior: o
-- lançamento **antigo** ficaria impossível de editar, porque a policy de UPDATE
-- governa a linha nova de todo UPDATE.
--
-- Quem garante a coerência é o seletor, que só oferece membro ativo. O banco não
-- julga. O custo aceito é `paid_by` podendo apontar para quem saiu — que é
-- exatamente o que a seção "Acertar contas" precisa mostrar, porque a dívida não
-- sai do espaço junto com a pessoa.
--
-- POR QUE `on delete set null` E NÃO `cascade`. `created_by` cascateia: apagar a
-- conta apaga os lançamentos dela, que é o desejado para o dono do dado. Aqui
-- não — o lançamento é do espaço, e apagar a conta de quem *pagou* o mercado da
-- república não pode evaporar a despesa de todo mundo. `set null` degrada para
-- "quem lançou", que é a leitura correta quando não se sabe mais quem pagou.
--
-- SYNC RULES NÃO MUDAM. `by_space` lê `select * from transactions`, e coluna
-- nova em tabela que já está num bucket **não exige republicar** (mesma
-- observação do cabeçalho da `20260801205317`). A republicação pendente é a da
-- `20260801214203`, por causa da tabela `expense_splits` — esta migration não a
-- resolve nem a agrava.
--
-- RLS NÃO MUDA. `paid_by` é coluna de `transactions`, governada pelas quatro
-- policies da `20260727151151`: ver é ser membro, escrever é ser admin/editor.
-- `transactions_insert_editor` continua exigindo `created_by = auth.uid()`, o
-- que é o que queremos — eu registro o acerto que **outra** pessoa pagou, então
-- `created_by` é meu e `paid_by` é dela.
-- =========================================================================

alter table public.transactions
  add column if not exists paid_by uuid
    references auth.users (id) on delete set null;

-- O advisor de performance acusa `unindexed_foreign_keys` sem isto, e o SQL do
-- saldo agrupa por esta coluna.
create index if not exists transactions_paid_by_idx
  on public.transactions (paid_by);

-- -------------------------------------------------------------------------
-- Nulo vira "quem lançou", no servidor.
--
-- `security definer` não é necessário: a função só lê colunas da linha que está
-- sendo escrita, sem tocar em outra tabela.
--
-- Dispara em `insert` e em `update of paid_by` — um UPDATE que não mencione a
-- coluna não precisa reescrevê-la, e não mencionar é o caso comum (mudar
-- descrição, categoria, valor).
-- -------------------------------------------------------------------------
create or replace function public.transactions_default_paid_by()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.paid_by := coalesce(new.paid_by, new.created_by);
  return new;
end;
$$;

-- Função de trigger não tem por que ser endpoint REST (tudo em `public` vira
-- `/rest/v1/rpc/<nome>`). O trigger segue disparando: a permissão é checada na
-- criação dele, não a cada linha.
revoke execute on function public.transactions_default_paid_by()
  from anon, authenticated, public;

drop trigger if exists transactions_default_paid_by on public.transactions;

create trigger transactions_default_paid_by
  before insert or update of paid_by on public.transactions
  for each row
  execute function public.transactions_default_paid_by();

-- As linhas que já existem: o trigger só governa escrita nova, e um UPDATE em
-- massa aqui seria o único jeito de a coluna ficar preenchida no histórico. Ele
-- **não** é feito de propósito — nulo já significa "quem lançou" para quem lê, e
-- reescrever 2.083 linhas moveria `updated_at` de todas elas, o que faria o
-- PowerSync reenviar o histórico inteiro para cada aparelho.
comment on column public.transactions.paid_by is
  'Quem pagou. Nulo significa quem lançou (created_by) — o trigger '
  'transactions_default_paid_by resolve na escrita, e o cliente faz o mesmo '
  'coalesce na linha local.';
