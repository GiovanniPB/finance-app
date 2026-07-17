-- =========================================================================
-- Espaços (spaces) + membership (space_members) — fundação multi-tenancy.
-- Ver ADR 0004: acesso por membership, não por dono. Funções SECURITY DEFINER
-- evitam a recursão de space_members consultando a si mesma na RLS.
-- =========================================================================

-- -------------------------------------------------------------------------
-- spaces: unidade de contexto financeiro (personal | household | group).
-- -------------------------------------------------------------------------
create table public.spaces (
  id                  uuid primary key default gen_random_uuid(),
  space_type          text not null
                        check (space_type in ('personal', 'household', 'group')),
  name                text not null check (char_length(name) between 1 and 120),
  owner_id            uuid not null references auth.users (id) on delete cascade,
  privacy_policy      text not null default 'shared_only'
                        check (privacy_policy in ('full_transparency', 'shared_only')),
  status              text not null default 'active'
                        check (status in ('active', 'archived')),
  settlement_currency text not null default 'BRL'
                        check (char_length(settlement_currency) = 3),
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index spaces_owner_id_idx on public.spaces (owner_id);

create trigger spaces_set_updated_at
  before update on public.spaces
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------------------
-- space_members: pertencimento de um usuário a um espaço, com papel.
-- -------------------------------------------------------------------------
create table public.space_members (
  id               uuid primary key default gen_random_uuid(),
  space_id         uuid not null references public.spaces (id) on delete cascade,
  user_id          uuid not null references auth.users (id) on delete cascade,
  role             text not null default 'editor'
                     check (role in ('admin', 'editor', 'viewer')),
  share_percentage numeric,
  status           text not null default 'active'
                     check (status in ('invited', 'active', 'left')),
  joined_at        timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (space_id, user_id)
);

create index space_members_user_id_idx on public.space_members (user_id);
create index space_members_space_id_idx on public.space_members (space_id);

create trigger space_members_set_updated_at
  before update on public.space_members
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------------------
-- Funções de autorização (SECURITY DEFINER: ignoram RLS por dentro, quebrando
-- a recursão de space_members). search_path vazio por segurança.
-- -------------------------------------------------------------------------
create or replace function public.is_space_member(_space_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.space_members m
    where m.space_id = _space_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

create or replace function public.has_space_role(_space_id uuid, _roles text[])
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.space_members m
    where m.space_id = _space_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role = any(_roles)
  );
$$;

-- Permite ao dono enxergar/gerenciar o espaço antes de existir a linha de
-- membership (bootstrap de criação, incl. writes offline vindos do PowerSync).
create or replace function public.is_space_owner(_space_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.spaces s
    where s.id = _space_id and s.owner_id = auth.uid()
  );
$$;

-- -------------------------------------------------------------------------
-- RLS: spaces
-- -------------------------------------------------------------------------
alter table public.spaces enable row level security;

create policy "spaces_select_member_or_owner"
  on public.spaces for select
  using (public.is_space_member(id) or public.is_space_owner(id));

create policy "spaces_insert_own"
  on public.spaces for insert
  with check (owner_id = auth.uid());

create policy "spaces_update_admin"
  on public.spaces for update
  using (public.has_space_role(id, array['admin']) or public.is_space_owner(id))
  with check (public.has_space_role(id, array['admin']) or public.is_space_owner(id));

-- -------------------------------------------------------------------------
-- RLS: space_members
-- -------------------------------------------------------------------------
alter table public.space_members enable row level security;

create policy "space_members_select_member"
  on public.space_members for select
  using (public.is_space_member(space_id) or public.is_space_owner(space_id));

create policy "space_members_insert_owner_or_admin"
  on public.space_members for insert
  with check (
    public.is_space_owner(space_id)
    or public.has_space_role(space_id, array['admin'])
  );

create policy "space_members_update_self_or_admin"
  on public.space_members for update
  using (user_id = auth.uid() or public.has_space_role(space_id, array['admin']))
  with check (user_id = auth.uid() or public.has_space_role(space_id, array['admin']));

create policy "space_members_delete_admin"
  on public.space_members for delete
  using (public.has_space_role(space_id, array['admin']));

-- -------------------------------------------------------------------------
-- Signup: cria profile + Espaço Pessoal + membership (admin). SECURITY DEFINER
-- => ignora RLS. Substitui a versão da migration inicial (apenas profile).
-- -------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  _space_id uuid;
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name');

  insert into public.spaces (space_type, name, owner_id, privacy_policy)
  values ('personal', 'Pessoal', new.id, 'shared_only')
  returning id into _space_id;

  insert into public.space_members (space_id, user_id, role, status)
  values (_space_id, new.id, 'admin', 'active');

  return new;
end;
$$;

-- -------------------------------------------------------------------------
-- PowerSync: WAL completo para updates/deletes. A publication `powersync` é
-- FOR ALL TABLES, então estas tabelas já entram automaticamente.
-- -------------------------------------------------------------------------
alter table public.spaces replica identity full;
alter table public.space_members replica identity full;
