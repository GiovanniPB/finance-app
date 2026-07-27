-- =========================================================================
-- Núcleo do Pilar 1: categories + transactions + budgets.
--
-- Todas com escopo de espaço e RLS por membership (ADR 0004), dinheiro em
-- inteiro de unidades mínimas (ADR 0006) e `replica identity full` para o
-- PowerSync capturar updates/deletes no WAL.
--
-- Duas convenções desta migration valem registro:
--
--  1. `amount_minor` é sempre POSITIVO; a direção do valor vem de `type`.
--     Guardar sinal na coluna permitiria "receita negativa" — dado
--     contraditório que nenhuma constraint pegaria. A camada `data` do Dart
--     converte para um `Money` com sinal na fronteira.
--
--  2. Cor de categoria é um ÍNDICE de paleta (`color_index`), não um hex livre.
--     O design system restringe categoria a seis matizes de baixa croma para
--     nenhuma categoria gritar mais alto que um valor; um hex livre deixaria o
--     usuário furar essa disciplina. Sem limite superior na constraint: o Dart
--     aplica módulo sobre o tamanho da paleta, então crescer a paleta nunca
--     invalida dado existente.
-- =========================================================================

-- -------------------------------------------------------------------------
-- categories
--
-- `space_id` nulo + `is_system` = categoria global pronta (PRD RN-1.2).
-- Categoria criada pelo usuário pertence a um espaço.
-- -------------------------------------------------------------------------
create table public.categories (
  id                 uuid primary key default gen_random_uuid(),
  space_id           uuid references public.spaces (id) on delete cascade,
  name               text not null check (char_length(name) between 1 and 60),
  icon_key           text not null default 'other'
                       check (char_length(icon_key) between 1 and 40),
  color_index        smallint check (color_index >= 0),
  is_system          boolean not null default false,
  parent_category_id uuid references public.categories (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  -- Sistema é sempre global; do usuário é sempre de um espaço.
  constraint categories_scope_ck check (
    (is_system and space_id is null)
    or (not is_system and space_id is not null)
  )
);

create index categories_space_id_idx on public.categories (space_id);
create index categories_parent_idx on public.categories (parent_category_id);

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

alter table public.categories enable row level security;

-- Sistema é visível a todos; do usuário, só a membros do espaço.
create policy "categories_select_system_or_member"
  on public.categories for select
  using (is_system or public.is_space_member(space_id));

-- Só admin/editor cria, e nunca uma categoria de sistema.
create policy "categories_insert_editor"
  on public.categories for insert
  with check (
    not is_system
    and public.has_space_role(space_id, array['admin', 'editor'])
  );

create policy "categories_update_editor"
  on public.categories for update
  using (
    not is_system
    and public.has_space_role(space_id, array['admin', 'editor'])
  )
  with check (
    not is_system
    and public.has_space_role(space_id, array['admin', 'editor'])
  );

create policy "categories_delete_editor"
  on public.categories for delete
  using (
    not is_system
    and public.has_space_role(space_id, array['admin', 'editor'])
  );

-- -------------------------------------------------------------------------
-- transactions
-- -------------------------------------------------------------------------
create table public.transactions (
  id             uuid primary key default gen_random_uuid(),
  space_id       uuid not null references public.spaces (id) on delete cascade,
  account_id     uuid references public.accounts (id) on delete set null,
  created_by     uuid not null references auth.users (id) on delete cascade,
  type           text not null
                   check (type in ('expense', 'income', 'transfer', 'savings')),
  -- Sempre positivo; a direção vem de `type` (ver cabeçalho).
  amount_minor   bigint not null check (amount_minor > 0),
  currency       text not null default 'BRL'
                   check (char_length(currency) = 3),
  category_id    uuid references public.categories (id) on delete set null,
  description    text check (char_length(description) <= 200),
  occurred_at    timestamptz not null default now(),
  source         text not null default 'manual'
                   check (source in ('manual', 'open_finance')),
  is_shared      boolean not null default false,
  ai_categorized boolean not null default false,
  recurrence_id  uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- A query da lista: por espaço, mais recente primeiro.
create index transactions_space_occurred_idx
  on public.transactions (space_id, occurred_at desc);
create index transactions_category_idx on public.transactions (category_id);
create index transactions_account_idx on public.transactions (account_id);

create trigger transactions_set_updated_at
  before update on public.transactions
  for each row execute function public.set_updated_at();

alter table public.transactions enable row level security;

create policy "transactions_select_member"
  on public.transactions for select
  using (public.is_space_member(space_id));

create policy "transactions_insert_editor"
  on public.transactions for insert
  with check (
    created_by = auth.uid()
    and public.has_space_role(space_id, array['admin', 'editor'])
  );

create policy "transactions_update_editor"
  on public.transactions for update
  using (public.has_space_role(space_id, array['admin', 'editor']))
  with check (public.has_space_role(space_id, array['admin', 'editor']));

create policy "transactions_delete_editor"
  on public.transactions for delete
  using (public.has_space_role(space_id, array['admin', 'editor']));

-- -------------------------------------------------------------------------
-- budgets — limite por categoria e período (PRD RN-1.3).
-- -------------------------------------------------------------------------
create table public.budgets (
  id           uuid primary key default gen_random_uuid(),
  space_id     uuid not null references public.spaces (id) on delete cascade,
  category_id  uuid not null
                 references public.categories (id) on delete cascade,
  amount_minor bigint not null check (amount_minor > 0),
  currency     text not null default 'BRL' check (char_length(currency) = 3),
  period       text not null default 'monthly'
                 check (period in ('monthly', 'weekly')),
  starts_at    date not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- Um orçamento por categoria/período/início dentro do espaço.
  unique (space_id, category_id, period, starts_at)
);

create index budgets_space_id_idx on public.budgets (space_id);

create trigger budgets_set_updated_at
  before update on public.budgets
  for each row execute function public.set_updated_at();

alter table public.budgets enable row level security;

create policy "budgets_select_member"
  on public.budgets for select
  using (public.is_space_member(space_id));

create policy "budgets_insert_editor"
  on public.budgets for insert
  with check (public.has_space_role(space_id, array['admin', 'editor']));

create policy "budgets_update_editor"
  on public.budgets for update
  using (public.has_space_role(space_id, array['admin', 'editor']))
  with check (public.has_space_role(space_id, array['admin', 'editor']));

create policy "budgets_delete_editor"
  on public.budgets for delete
  using (public.has_space_role(space_id, array['admin', 'editor']));

-- -------------------------------------------------------------------------
-- Categorias de sistema (RN-1.2: "fixas prontas, sempre disponíveis").
--
-- UUIDs fixos de propósito: sobrevivem a `supabase db reset`, o que mantém
-- testes e seeds determinísticos. `icon_key` é uma chave estável mapeada para
-- IconData no Dart — o banco não guarda codepoint de fonte.
-- -------------------------------------------------------------------------
insert into public.categories (id, name, icon_key, color_index, is_system)
values
  ('00000000-0000-4000-8000-000000000001', 'Alimentação', 'food', 0, true),
  ('00000000-0000-4000-8000-000000000002', 'Transporte', 'transport', 1, true),
  ('00000000-0000-4000-8000-000000000003', 'Moradia', 'home', 3, true),
  ('00000000-0000-4000-8000-000000000004', 'Saúde', 'health', 4, true),
  ('00000000-0000-4000-8000-000000000005', 'Lazer', 'leisure', 2, true),
  ('00000000-0000-4000-8000-000000000006', 'Educação', 'education', 1, true),
  ('00000000-0000-4000-8000-000000000007', 'Compras', 'shopping', 2, true),
  ('00000000-0000-4000-8000-000000000008', 'Assinaturas', 'subscriptions', 2, true),
  ('00000000-0000-4000-8000-000000000009', 'Salário', 'salary', 0, true),
  ('00000000-0000-4000-8000-00000000000a', 'Outros', 'other', 5, true);

-- -------------------------------------------------------------------------
-- PowerSync: WAL completo. A publication `powersync` é FOR ALL TABLES, então
-- estas tabelas entram automaticamente.
-- -------------------------------------------------------------------------
alter table public.categories replica identity full;
alter table public.transactions replica identity full;
alter table public.budgets replica identity full;
