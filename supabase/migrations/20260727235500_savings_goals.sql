-- =========================================================================
-- Pilar 3, primeira metade: savings_goals + savings_contributions.
--
-- Escopo de espaço e RLS por membership (ADR 0004), dinheiro em inteiro de
-- unidades mínimas (ADR 0006) e `replica identity full` para o PowerSync
-- capturar updates/deletes no WAL.
--
-- Quatro decisões desta migration valem registro:
--
--  1. NÃO EXISTE COLUNA `current_amount`. O PRD §5.2 a lista, e a RN-3.3 diz
--     que ela "soma as contribuições confirmadas" — ou seja, é uma soma, não um
--     fato. Num app offline-first uma coluna que precisa ser igual a uma
--     agregação desincroniza em silêncio: dois aparelhos adicionando
--     contribuição offline gravam dois valores diferentes para a mesma verdade,
--     e o último upload ganha. O progresso é derivado das contribuições na
--     camada `data`, exatamente como `BudgetUsage` deriva o gasto de
--     `transactions` em vez de manter um acumulado.
--
--  2. `savings_contributions.space_id` é DENORMALIZADO de propósito. A
--     contribuição pertence à meta (`goal_id`), e o RLS poderia alcançar o
--     espaço por subquery. As **sync rules do PowerSync não fazem join**: um
--     bucket é `select * from t where space_id = bucket.space_id`. Sem a coluna,
--     a tabela não teria como entrar num bucket por espaço. O trigger
--     `savings_contributions_inherit_space` mantém a coluna honesta — o cliente
--     não precisa acertá-la, e não consegue mentir nela.
--
--  3. `recurring_challenge` fica FORA do check de `goal_type`, apesar de estar
--     no PRD (RN-3.1). Aceitar no banco um tipo que o app não sabe renderizar
--     produz linha órfã com cara de dado válido; crescer um check depois é
--     barato (mesmo raciocínio de `account_type` na migration 20260727210000).
--
--  4. Contribuição é sempre POSITIVA (`amount_minor > 0`). Retirar da poupança
--     não é "contribuição negativa" — é outro evento, com outra semântica de
--     streak (RN-3.4) e de feed. Quando existir, será uma linha própria com
--     tipo próprio, não um sinal invertido aqui.
-- =========================================================================

-- -------------------------------------------------------------------------
-- savings_goals — os três tipos de meta em uso (RN-3.1).
--
-- Cada tipo usa um subconjunto diferente das colunas, e o check de forma
-- garante que a linha só existe preenchida de um jeito que faça sentido:
--
--   objective         → valor-alvo, prazo OPCIONAL ("reserva de emergência"
--                       legitimamente não tem data; sem prazo não há ritmo a
--                       comparar, e a UI não desenha a marca de ritmo)
--   fixed_amount      → valor por mês, sem prazo
--   percentage_income → percentual da renda do mês, sem valor e sem prazo
-- -------------------------------------------------------------------------
create table public.savings_goals (
  id                  uuid primary key default gen_random_uuid(),
  space_id            uuid not null
                        references public.spaces (id) on delete cascade,
  created_by          uuid not null references auth.users (id) on delete cascade,
  goal_type           text not null
                        check (
                          goal_type in (
                            'objective', 'fixed_amount', 'percentage_income'
                          )
                        ),
  name                text not null check (char_length(name) between 1 and 80),
  -- Valor-alvo (objective) ou valor mensal (fixed_amount). Sempre positivo.
  target_amount_minor bigint check (target_amount_minor > 0),
  currency            text not null default 'BRL'
                        check (char_length(currency) = 3),
  target_date         date,
  -- Fatia da renda, em pontos percentuais inteiros. `smallint` em vez de
  -- `numeric`: meta de 12,5% da renda não é uma necessidade real, e um inteiro
  -- 1–100 é o domínio que a UI oferece (presets de 5 em 5).
  percentage          smallint check (percentage between 1 and 100),
  -- Conta onde o dinheiro é guardado. Opcional: dá para ter meta antes de
  -- cadastrar a conta, e `on delete set null` faz a meta sobreviver à conta.
  linked_account_id   uuid references public.accounts (id) on delete set null,
  status              text not null default 'active'
                        check (status in ('active', 'completed', 'paused')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  -- `else false` de propósito: se o check de `goal_type` crescer sem que este
  -- cresça junto, a inserção falha em vez de gravar uma linha sem forma.
  constraint savings_goals_shape_ck check (
    case goal_type
      when 'objective' then
        target_amount_minor is not null and percentage is null
      when 'fixed_amount' then
        target_amount_minor is not null and percentage is null
          and target_date is null
      when 'percentage_income' then
        percentage is not null and target_amount_minor is null
          and target_date is null
      else false
    end
  )
);

create index savings_goals_space_id_idx on public.savings_goals (space_id);
create index savings_goals_account_idx
  on public.savings_goals (linked_account_id);

create trigger savings_goals_set_updated_at
  before update on public.savings_goals
  for each row execute function public.set_updated_at();

alter table public.savings_goals enable row level security;

create policy "savings_goals_select_member"
  on public.savings_goals for select
  using (public.is_space_member(space_id));

-- Criar/editar meta é ação de admin ou editor (PRD §7).
create policy "savings_goals_insert_editor"
  on public.savings_goals for insert
  with check (
    created_by = auth.uid()
    and public.has_space_role(space_id, array['admin', 'editor'])
  );

create policy "savings_goals_update_editor"
  on public.savings_goals for update
  using (public.has_space_role(space_id, array['admin', 'editor']))
  with check (public.has_space_role(space_id, array['admin', 'editor']));

create policy "savings_goals_delete_editor"
  on public.savings_goals for delete
  using (public.has_space_role(space_id, array['admin', 'editor']));

-- -------------------------------------------------------------------------
-- savings_contributions — o que faz a meta andar (RN-3.2, RN-3.3).
--
-- `detected_via` + `confirmed` modelam os três caminhos da RN-3.2 numa única
-- tabela:
--
--   manual      + confirmed=true   → "guardei R$ X" (o único caminho na Fase 1)
--   open_finance + confirmed=false → transferência detectada, aguardando o sim
--   open_finance + confirmed=true  → detectada e confirmada pelo usuário
--
-- Só contribuição CONFIRMADA entra no progresso (RN-3.3). A ingestão da Pluggy
-- (ADR 0005) grava com `confirmed=false` e nunca toca em `confirmed` depois:
-- essa coluna é do usuário, não do provedor.
-- -------------------------------------------------------------------------
create table public.savings_contributions (
  id             uuid primary key default gen_random_uuid(),
  goal_id        uuid not null
                   references public.savings_goals (id) on delete cascade,
  -- Denormalizado para as sync rules poderem bucketizar sem join (ver
  -- cabeçalho, item 2). Mantido pelo trigger abaixo.
  space_id       uuid not null references public.spaces (id) on delete cascade,
  created_by     uuid not null references auth.users (id) on delete cascade,
  amount_minor   bigint not null check (amount_minor > 0),
  currency       text not null default 'BRL' check (char_length(currency) = 3),
  detected_via   text not null default 'manual'
                   check (detected_via in ('open_finance', 'manual')),
  confirmed      boolean not null default true,
  contributed_at timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Manual implica confirmado: quem digitou o valor já o confirmou. Só o que
  -- foi detectado por terceiro pode estar pendente de um sim.
  constraint savings_contributions_manual_confirmed_ck check (
    detected_via <> 'manual' or confirmed
  )
);

-- A query do detalhe: contribuições de uma meta, mais recentes primeiro.
create index savings_contributions_goal_idx
  on public.savings_contributions (goal_id, contributed_at desc);
create index savings_contributions_space_idx
  on public.savings_contributions (space_id);
-- Índice parcial: "o que falta confirmar" é sempre um subconjunto pequeno.
create index savings_contributions_pending_idx
  on public.savings_contributions (space_id)
  where not confirmed;

create trigger savings_contributions_set_updated_at
  before update on public.savings_contributions
  for each row execute function public.set_updated_at();

-- O `space_id` da contribuição é o da meta, sempre. Derivar no trigger em vez
-- de confiar no cliente: a coluna existe por necessidade de sync (ver
-- cabeçalho), e um cliente que a preenchesse errado moveria a contribuição para
-- outro bucket — vazamento entre espaços com cara de bug de UI.
create or replace function public.savings_contributions_inherit_space()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select g.space_id into new.space_id
  from public.savings_goals g
  where g.id = new.goal_id;

  if new.space_id is null then
    raise exception 'Meta % não existe', new.goal_id;
  end if;

  return new;
end;
$$;

create trigger savings_contributions_inherit_space
  before insert or update of goal_id on public.savings_contributions
  for each row execute function public.savings_contributions_inherit_space();

-- Tira a função do alcance da API REST.
--
-- Toda função em `public` vira endpoint `/rest/v1/rpc/<nome>` no Supabase, e o
-- `get_advisors` acusa `SECURITY DEFINER` alcançável por `anon`. Chamar esta
-- daqui direto não faria nada (o Postgres recusa função de trigger fora de um
-- trigger), mas função de trigger não tem por que estar na superfície pública.
-- O trigger continua funcionando: a permissão de execução é checada quando o
-- trigger é criado, não a cada disparo.
revoke execute on function public.savings_contributions_inherit_space()
  from anon, authenticated, public;

alter table public.savings_contributions enable row level security;

create policy "savings_contributions_select_member"
  on public.savings_contributions for select
  using (public.is_space_member(space_id));

-- O INSERT é validado pelo espaço da META, e não pelo `space_id` da linha.
--
-- Os dois funcionariam: o Postgres aplica o `with check` do RLS **depois** dos
-- triggers `before`, então a coluna já estaria corrigida na hora da checagem.
-- A subquery é preferida por não depender dessa ordem — a autorização passa a
-- ler a fonte autoritativa (a meta) em vez de um valor que outra parte do
-- sistema precisou consertar primeiro.
create policy "savings_contributions_insert_editor"
  on public.savings_contributions for insert
  with check (
    created_by = auth.uid()
    and public.has_space_role(
      (select g.space_id from public.savings_goals g where g.id = goal_id),
      array['admin', 'editor']
    )
  );

create policy "savings_contributions_update_editor"
  on public.savings_contributions for update
  using (public.has_space_role(space_id, array['admin', 'editor']))
  with check (
    public.has_space_role(
      (select g.space_id from public.savings_goals g where g.id = goal_id),
      array['admin', 'editor']
    )
  );

create policy "savings_contributions_delete_editor"
  on public.savings_contributions for delete
  using (public.has_space_role(space_id, array['admin', 'editor']));

-- -------------------------------------------------------------------------
-- PowerSync: WAL completo. A publication `powersync` é FOR ALL TABLES, então
-- estas tabelas entram automaticamente.
--
-- ⚠️ TABELA NOVA EXIGE REPUBLICAR AS SYNC RULES no dashboard do PowerSync.
-- Coluna nova não exige (os buckets usam `select *`), mas tabela nova sim — e o
-- sintoma de esquecer é tabela vazia no cliente, sem erro nenhum.
-- -------------------------------------------------------------------------
alter table public.savings_goals replica identity full;
alter table public.savings_contributions replica identity full;
