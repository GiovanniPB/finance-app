# ADR 0004 — Multi-tenancy por Espaços (RLS por membership)

- Status: aceito
- Data: 2026-07-17

## Contexto

O PRD organiza todo o produto em torno do conceito de **Espaço** (`personal`,
`household`, `group`). Um usuário pertence a vários espaços, e a visibilidade dos
dados (transações, orçamentos, metas) depende de ele ser **membro** do espaço —
não de ser o "dono" da linha. A base atual usa RLS por dono
(`owner_id = auth.uid()`), que não expressa "membros de um household veem tudo do
household".

## Decisão

**Acesso por membership de espaço.** Toda tabela com escopo de espaço tem
`space_id` e é protegida por RLS baseada em pertencimento, via funções
`SECURITY DEFINER` que evitam a recursão de `space_members` consultando a si
mesma:

```sql
create function public.is_space_member(_space_id uuid) returns boolean
  language sql security definer stable set search_path = '' as $$
    select exists (
      select 1 from public.space_members m
      where m.space_id = _space_id and m.user_id = auth.uid()
        and m.status = 'active'
    );
  $$;

create function public.has_space_role(_space_id uuid, _roles text[]) returns boolean
  language sql security definer stable set search_path = '' as $$
    select exists (
      select 1 from public.space_members m
      where m.space_id = _space_id and m.user_id = auth.uid()
        and m.status = 'active' and m.role = any(_roles)
    );
  $$;
```

- **Leitura**: `using (public.is_space_member(space_id))`.
- **Escrita**: `with check (public.has_space_role(space_id, array['admin','editor']))`.

**Espaço Pessoal também é membership.** No signup criamos o `profiles`, o espaço
`personal` e a linha `space_members` (role `admin`). Assim pessoal, household e
group passam pelo **mesmo** mecanismo — sem condicionais `if personal` espalhadas.

**`accounts` é a exceção (soberania do dono).** Conta pertence ao usuário
(`owner_id`) e pode ser vinculada a um household (`linked_space_id`). Visível para
o dono **ou** para membros do household ao qual foi vinculada; vínculo e escrita
só pelo dono, independentemente do papel no espaço.

## Consequências

- As regras de privacidade do PRD emergem da estrutura, sem código extra:
  - Transação pessoal (space pessoal) nunca vaza para um group (o outro não é
    membro do espaço pessoal).
  - Household com `full_transparency`: ambos são membros → ambos veem.
  - Group: membros só veem o que foi lançado naquele group (`space_id`).
- **Impacto no cliente**: o SQLite local passa a conter **vários espaços** ao
  mesmo tempo. Queries de repositório precisam filtrar por `space_id` do espaço
  ativo (`activeSpaceProvider`). Antes, `SELECT * FROM accounts` bastava porque só
  havia um dono.
- Funções `SECURITY DEFINER` precisam de `set search_path = ''` (segurança) e são
  auditadas via `get_advisors` a cada mudança de schema.

## Alternativas descartadas

- **Tipo "compartilhado genérico"** em vez de `household`/`group` separados: geraria
  condicionais `if tipo == casal` por toda a base (ver PRD §4.2).
- **RLS por dono + filtragem no app**: vazaria dados de outros membros no sync e
  quebraria o modelo offline-first.
