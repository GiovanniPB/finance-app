-- =========================================================================
-- Schema inicial: profiles + accounts (vertical slice de prova offline-first)
-- Todas as tabelas: PK uuid, owner_id, timestamps, RLS por dono, trigger de
-- updated_at. As tabelas espelham o schema local do PowerSync (packages/database).
-- =========================================================================

-- Extensão para gen_random_uuid() (disponível no Postgres do Supabase).
create extension if not exists "pgcrypto";

-- -------------------------------------------------------------------------
-- Função utilitária: mantém updated_at em toda escrita.
-- -------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -------------------------------------------------------------------------
-- profiles: 1:1 com auth.users. Criado automaticamente no signup.
-- -------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Cria o profile automaticamente quando um usuário se registra.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -------------------------------------------------------------------------
-- accounts: entidade de domínio da prova (uma conta financeira do usuário).
-- -------------------------------------------------------------------------
create table public.accounts (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references auth.users (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 120),
  currency   text not null default 'BRL' check (char_length(currency) = 3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index accounts_owner_id_idx on public.accounts (owner_id);

create trigger accounts_set_updated_at
  before update on public.accounts
  for each row execute function public.set_updated_at();

alter table public.accounts enable row level security;

create policy "accounts_select_own"
  on public.accounts for select
  using (auth.uid() = owner_id);

create policy "accounts_insert_own"
  on public.accounts for insert
  with check (auth.uid() = owner_id);

create policy "accounts_update_own"
  on public.accounts for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "accounts_delete_own"
  on public.accounts for delete
  using (auth.uid() = owner_id);
