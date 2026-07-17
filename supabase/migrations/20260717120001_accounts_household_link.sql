-- =========================================================================
-- accounts: vínculo opcional a um household + visibilidade por membership.
-- Ver ADR 0004: a conta pertence ao dono (soberania). Quando vinculada a um
-- household (linked_space_id), os membros desse espaço também a enxergam.
-- Escrita/vínculo continuam exclusivos do dono.
-- =========================================================================

alter table public.accounts
  add column linked_space_id uuid references public.spaces (id) on delete set null;

create index accounts_linked_space_id_idx on public.accounts (linked_space_id);

-- Amplia a leitura: dono OU membro do household ao qual a conta foi vinculada.
drop policy "accounts_select_own" on public.accounts;

create policy "accounts_select_own_or_linked"
  on public.accounts for select
  using (
    owner_id = auth.uid()
    or (
      linked_space_id is not null
      and public.is_space_member(linked_space_id)
    )
  );

-- Insert/update/delete permanecem restritos ao dono (policies da migration
-- inicial: accounts_insert_own, accounts_update_own, accounts_delete_own).
