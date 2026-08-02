-- =========================================================================
-- dividir-despesa: a parte de cada pessoa numa despesa de grupo.
--
-- POR QUE `space_id` ESTÁ AQUI, SE A PARTE JÁ APONTA PARA O LANÇAMENTO.
-- Aplicação direta do ADR 0011: as sync rules do PowerSync não fazem join, e um
-- bucket é `select * from t where space_id = bucket.space_id`. Sem a coluna, a
-- parte seria invisível para todo mundo — o lançamento sabe o espaço, mas a sync
-- rule não tem como chegar até ele. `savings_contributions.space_id` existe pela
-- mesma razão desde a `20260727235500`.
--
-- ⚠️ TABELA NOVA EXIGE REPUBLICAR AS SYNC RULES À MÃO. Diferente da
-- `20260801205317`, que só somou coluna a uma tabela já bucketizada. Esquecer se
-- manifesta como tela vazia **sem erro nenhum**: o sheet de edição ofereceria
-- "Dividir igualmente" para um lançamento que já está dividido.
--
-- POR QUE NÃO HÁ CONSTRAINT SOBRE A SOMA DAS PARTES. A tentação é um trigger
-- que recuse quando `sum(amount_minor) <> transactions.amount_minor`. Ele
-- quebraria o app: o upload do PowerSync sobe linha por linha, então existe um
-- instante em que duas das três partes chegaram e a soma não fecha. Uma regra
-- assim recusaria o batch inteiro, e o `SupabaseConnector` descarta batch
-- recusado — a divisão apareceria aplicada no aparelho e sumiria no checkpoint
-- seguinte, que é a armadilha nº 4 deste repo.
--
-- Quem garante que a soma fecha é a camada `data`, escrevendo as N partes e a
-- marca `is_shared` **na mesma** `writeTransaction` local, com o rateio vindo de
-- `Money.split()` (método do maior resto: a soma é sempre igual ao total).
--
-- POR QUE `amount_minor >= 0` E NÃO `> 0`. R$ 0,01 entre três pessoas dá uma
-- parte de 1 centavo e duas de zero. Omitir as duas pessoas mentiria sobre quem
-- participou da despesa; gravar zero diz a verdade. `transactions.amount_minor`
-- continua `> 0` — lançamento de valor zero não existe, parte de valor zero
-- existe.
-- =========================================================================

create table public.expense_splits (
  id             uuid primary key default gen_random_uuid(),
  transaction_id uuid not null
                   references public.transactions (id) on delete cascade,
  -- Denormalizado. Ver o cabeçalho; mantido pelo trigger abaixo.
  space_id       uuid not null references public.spaces (id) on delete cascade,
  user_id        uuid not null references auth.users (id) on delete cascade,
  amount_minor   bigint not null check (amount_minor >= 0),
  currency       text not null default 'BRL'
                   check (char_length(currency) = 3),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- Uma parte por pessoa por lançamento. É a rede que impede o toque duplo em
  -- "Dividir igualmente" de gerar rateio dobrado; o caminho normal de refazer é
  -- apagar e reinserir.
  unique (transaction_id, user_id)
);

-- `transaction_id` já é coberto pelo índice do `unique` acima (coluna líder).
-- Estes dois cobrem os outros dois FKs — sem eles o advisor de performance
-- acusa `unindexed_foreign_keys`, e o de `space_id` é o que a sync rule usa.
create index expense_splits_space_id_idx
  on public.expense_splits (space_id);
create index expense_splits_user_id_idx
  on public.expense_splits (user_id);

create trigger expense_splits_set_updated_at
  before update on public.expense_splits
  for each row execute function public.set_updated_at();

-- O PowerSync captura update e delete pelo WAL só com a linha inteira.
alter table public.expense_splits replica identity full;

-- -------------------------------------------------------------------------
-- Espaço e moeda vêm do lançamento, não do cliente.
--
-- `security definer` porque a função lê `transactions` de dentro de um INSERT
-- feito pelo papel `authenticated`, e a policy de SELECT de `transactions`
-- exige ser membro do espaço — o que é verdade no caminho normal, mas depender
-- disso seria depender de a ordem de avaliação da RLS coincidir.
--
-- Herdar em vez de confiar fecha dois defeitos de uma vez: parte gravada no
-- espaço errado (que a tornaria visível a quem não deve) e parte em moeda
-- diferente da do lançamento (que faria a soma não fechar por motivo invisível).
-- -------------------------------------------------------------------------
create or replace function public.expense_splits_inherit_from_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select t.space_id, t.currency
    into new.space_id, new.currency
  from public.transactions t
  where t.id = new.transaction_id;

  if new.space_id is null then
    raise exception 'Lançamento % não existe', new.transaction_id;
  end if;

  return new;
end;
$$;

-- Função de trigger não tem por que ser endpoint REST (tudo em `public` vira
-- `/rest/v1/rpc/<nome>`). O trigger segue disparando: a permissão é checada na
-- criação dele, não a cada linha.
revoke execute on function public.expense_splits_inherit_from_transaction()
  from anon, authenticated, public;

create trigger expense_splits_inherit_from_transaction
  before insert or update of transaction_id on public.expense_splits
  for each row
  execute function public.expense_splits_inherit_from_transaction();

-- -------------------------------------------------------------------------
-- RLS: espelha `transactions`. Ver é ser membro; escrever é poder lançar.
--
-- As policies chamam `private.…` e não `public.…` — as três funções de apoio
-- saíram do schema exposto na `20260728030625`, e a regra para fatias novas está
-- no `AGENTS.md`.
--
-- Não há policy de `delete` em `transactions` porque lá o delete é do autor; aqui
-- desfazer a divisão é apagar as partes, e quem pode lançar pode desfazer. Um
-- `viewer` não apaga rateio de ninguém.
-- -------------------------------------------------------------------------
alter table public.expense_splits enable row level security;

create policy "expense_splits_select_member"
  on public.expense_splits for select
  using (private.is_space_member(space_id));

create policy "expense_splits_insert_editor"
  on public.expense_splits for insert
  with check (private.has_space_role(space_id, array['admin', 'editor']));

create policy "expense_splits_update_editor"
  on public.expense_splits for update
  using (private.has_space_role(space_id, array['admin', 'editor']))
  with check (private.has_space_role(space_id, array['admin', 'editor']));

create policy "expense_splits_delete_editor"
  on public.expense_splits for delete
  using (private.has_space_role(space_id, array['admin', 'editor']));
