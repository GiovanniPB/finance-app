-- =========================================================================
-- Fecha a fatia de poupança: a contribuição passa a apontar para o lançamento
-- que a produziu.
--
-- O PROBLEMA QUE ISTO RESOLVE. "Guardei um valor" gravava só
-- `savings_contributions`. O dinheiro andava na meta e não andava em lugar
-- nenhum mais: não entrava em `MonthSummary.outflow`, não mexia no saldo do
-- mês, não aparecia na lista de lançamentos. Guardar R$ 500 era invisível para
-- o resto do app. O tipo `savings` de `transactions` existe exatamente para
-- este evento — o comentário dele diz "conta como saída porque o dinheiro deixa
-- o saldo gastável mesmo sem ser despesa" — e nada o produzia.
--
-- A DECISÃO. Guardar dinheiro é **um evento com duas faces**: um lançamento
-- (o dinheiro saiu do saldo gastável) e uma contribuição (a meta andou). As
-- duas linhas nascem juntas, na mesma transação de escrita, e esta coluna é o
-- que as amarra.
--
-- Três consequências que valem registro:
--
--  1. A COLUNA VIVE NA CONTRIBUIÇÃO, não no lançamento. A contribuição é a
--     face opcional: existe lançamento sem meta (todo gasto comum), não existe
--     contribuição sem dinheiro tendo saído. Pôr `savings_goal_id` em
--     `transactions` daria uma coluna nula em ~100% das linhas da tabela mais
--     movimentada do app.
--
--  2. `on delete cascade`, e não `set null`. Se o lançamento deixa de existir,
--     o dinheiro não saiu — e uma contribuição que sobrevivesse ao lançamento
--     faria a meta mostrar progresso de dinheiro que o extrato diz que nunca
--     se moveu. É a mesma família de desincronização que o item 1 do cabeçalho
--     da 20260727235500 evita ao não ter coluna `current_amount`.
--
--     A direção contrária é deliberadamente diferente: excluir a **meta** apaga
--     as contribuições dela (cascade que já existia) e **deixa os lançamentos
--     de pé**. O dinheiro saiu de verdade; quem desistiu foi a meta.
--
--  3. `unique` em vez de índice comum. Um lançamento não pode financiar duas
--     metas: seriam R$ 500 saindo do saldo e R$ 1.000 de progresso somado.
--     Nulo não conflita com nulo no Postgres, então a coluna segue opcional —
--     que é o que a ingestão do Open Finance precisa enquanto não existe.
-- =========================================================================

alter table public.savings_contributions
  add column transaction_id uuid
    references public.transactions (id) on delete cascade;

-- Um lançamento financia no máximo uma contribuição (ver cabeçalho, item 3).
alter table public.savings_contributions
  add constraint savings_contributions_transaction_uq unique (transaction_id);

comment on column public.savings_contributions.transaction_id is
  'Lançamento (type = savings) que produziu esta contribuição. Nulo em '
  'contribuição sem lançamento — o que a ingestão do Open Finance vai gravar '
  'antes de haver um lançamento nosso para apontar.';

-- -------------------------------------------------------------------------
-- O trigger de espaço passa a validar o lançamento também.
--
-- Mesmo motivo pelo qual ele já derivava `space_id` da meta: o cliente não
-- precisa acertar, e não consegue mentir. Sem esta checagem, um cliente
-- poderia apontar `transaction_id` para um lançamento de outro espaço — o RLS
-- de `transactions` impede *ler* aquela linha, mas o sucesso ou a falha da FK
-- já diria se ela existe.
--
-- O **tipo** do lançamento não é validado de propósito. Hoje só o caminho
-- manual grava, e ele grava `savings`; amanhã a ingestão da Pluggy (ADR 0005)
-- pode querer ligar uma `transfer` detectada para conta alvo de poupança, e um
-- check aqui a obrigaria a mentir no tipo para conseguir gravar.
-- -------------------------------------------------------------------------
create or replace function public.savings_contributions_inherit_space()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  transaction_space uuid;
begin
  select g.space_id into new.space_id
  from public.savings_goals g
  where g.id = new.goal_id;

  if new.space_id is null then
    raise exception 'Meta % não existe', new.goal_id;
  end if;

  if new.transaction_id is not null then
    select t.space_id into transaction_space
    from public.transactions t
    where t.id = new.transaction_id;

    if transaction_space is distinct from new.space_id then
      raise exception 'Lançamento % não pertence ao espaço da meta %',
        new.transaction_id, new.goal_id;
    end if;
  end if;

  return new;
end;
$$;

-- Recriado porque a lista de colunas do `update of` cresceu: sem
-- `transaction_id` nela, trocar só o vínculo não passaria pela validação acima.
drop trigger savings_contributions_inherit_space
  on public.savings_contributions;

create trigger savings_contributions_inherit_space
  before insert or update of goal_id, transaction_id
  on public.savings_contributions
  for each row execute function public.savings_contributions_inherit_space();

-- `create or replace` preserva o ACL, mas o revoke é reafirmado para o caso de
-- a função ser recriada de um dump: função de trigger não tem por que estar na
-- superfície REST (ver a nota na migration 20260727235500).
revoke execute on function public.savings_contributions_inherit_space()
  from anon, authenticated, public;
