-- =========================================================================
-- Gestão de membro: fecha três furos de escalonamento que a fatia de espaços
-- compartilhados deixou abertos, e só então libera "trocar papel", "remover"
-- e "sair".
--
-- Os três foram **medidos** contra este banco, com dois usuários de verdade
-- criados e apagados no mesmo script, antes de escrever uma linha de correção:
--
--   | tentativa                                 | antes            |
--   |-------------------------------------------|------------------|
--   | editor `set role='admin'` na própria linha| **1 linha** FURO |
--   | admin rebaixa a linha do **dono**         | **1 linha** FURO |
--   | admin reescreve `spaces.owner_id`         | **permitido**    |
--   | editor renomeia o espaço                  | 0 linhas ok      |
--   | membro sai sozinho (`status='left'`)      | 1 linha ok       |
--   | admin remove membro                       | 1 linha ok       |
--
-- A causa dos dois primeiros é o mesmo ramo: a policy de UPDATE era
--
--     using       (user_id = auth.uid() or has_space_role(space_id,['admin']))
--     with check  (user_id = auth.uid() or has_space_role(space_id,['admin']))
--
-- "é a minha linha" autoriza **qualquer** mudança nela, inclusive a coluna que
-- decide o que eu posso fazer. Uma policy é boa para dizer *quais linhas*, e
-- ruim para dizer *quais colunas* — não existe `OLD` numa policy, então ela não
-- consegue perguntar "esta coluna mudou?".
--
-- Daí a divisão desta migration: **policy separa linhas, trigger congela
-- colunas.**
--
-- ─────────────────────────────────────────────────────────────────────────
-- O QUE A MEDIÇÃO ENSINOU DE QUEBRA, E QUE VALE PARA AS PRÓXIMAS TABELAS
--
-- Duas tentativas que eu esperava ver passar foram barradas, e o motivo
-- generaliza o bug da migration 20260728204229:
--
--   • membro movendo a própria linha para outro espaço → `42501`
--   • membro removido reativando a si mesmo            → 0 linhas
--
-- **A policy de SELECT governa a linha velha e a linha nova de todo UPDATE.**
-- A velha porque o `WHERE` precisa achá-la (invisível => 0 linhas, em
-- silêncio); a nova porque o comando ainda a lê depois de escrita (invisível
-- => `42501`). Mudar `space_id` para um espaço de que não sou membro produz uma
-- linha nova invisível a mim — e é isso, não a policy de UPDATE, que barra a
-- mudança.
--
-- É a mesma regra do espaço que sumia, vista do outro lado: lá a linha nascia
-- invisível a si mesma; aqui ela *ficaria* invisível depois do UPDATE.
--
-- E é por isso que **sair** funciona: `status='left'` deixa `is_space_member`
-- falso, mas a função é `stable` e lê o snapshot do início do comando, onde eu
-- ainda estou `active`. Funciona por semântica de snapshot, o que é frágil
-- demais para se apoiar. O ramo `user_id = auth.uid()` acrescentado ao SELECT
-- abaixo torna isso explícito: **eu sempre enxergo o meu próprio vínculo**,
-- inclusive depois de sair. Sair passa a não depender de sorte.
--
-- ─────────────────────────────────────────────────────────────────────────
-- POR QUE ISSO É URGENTE NUM APP OFFLINE-FIRST
--
-- O `SupabaseConnector` descarta o batch em `PostgrestException` para não
-- travar a fila. Escrita recusada pela RLS, portanto, **não** vira erro na
-- tela: ela aparece aplicada e some no checkpoint seguinte. Um furo de RLS aqui
-- não é só "o servidor deixou"; é o cliente exibindo um estado que o servidor
-- nunca aceitou — ou o contrário. Regra que o servidor recusa, o app também
-- precisa recusar antes de escrever (ver `SpacePermissions`, no domínio).
-- =========================================================================

-- -------------------------------------------------------------------------
-- SELECT: acrescenta "a minha própria linha, sempre".
--
-- Sem isto, quem sai deixa de enxergar o registro de que esteve ali, e — pior —
-- o UPDATE que **faz** a pessoa sair passa a depender de semântica de snapshot
-- para ser aceito. Não afrouxa nada: o `space_id` de um espaço de que participei
-- é informação que eu já tinha.
-- -------------------------------------------------------------------------
drop policy if exists "space_members_select_member" on public.space_members;

create policy "space_members_select_member_or_self"
  on public.space_members for select
  using (
    private.is_space_member(space_id)
    or private.is_space_owner(space_id)
    or user_id = auth.uid()
  );

-- -------------------------------------------------------------------------
-- UPDATE, em duas policies em vez de uma.
--
-- Policies permissivas são unidas por OR, então separar não é só organização:
-- é o que permite dar poderes **diferentes** a "sou admin" e a "é a minha
-- linha", que era exatamente o que a versão única não conseguia dizer.
-- -------------------------------------------------------------------------
drop policy if exists "space_members_update_self_or_admin"
  on public.space_members;

-- Admin do espaço: gestão completa das linhas do espaço (papel, cota, remoção).
create policy "space_members_update_admin"
  on public.space_members for update
  using (private.has_space_role(space_id, array['admin']))
  with check (private.has_space_role(space_id, array['admin']));

-- A pessoa, sobre si mesma: **uma** transição, sair.
--
-- O `with check` fixa `status = 'left'` como único resultado aceito. É o que
-- fecha os dois furos de uma vez: promover-se a admin exige um resultado com
-- outro `status`, e reativar-se depois de removido exige `status = 'active'`.
create policy "space_members_leave_self"
  on public.space_members for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and status = 'left');

-- -------------------------------------------------------------------------
-- Trigger: o que a policy não alcança — colunas que não mudam nunca, e a linha
-- do dono.
--
-- `security definer` de propósito: a checagem lê `spaces.owner_id`, e sob
-- `security invoker` a RLS poderia esconder a linha e devolver `NULL` — a
-- guarda passaria calada justamente no caso que ela existe para barrar.
-- -------------------------------------------------------------------------
create or replace function public.space_members_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  _owner uuid;
begin
  -- Mudar `space_id` seria entrar num espaço por UPDATE; mudar `user_id` seria
  -- dar o próprio assento a outra pessoa. Hoje a policy de SELECT já barra o
  -- primeiro por efeito colateral (ver o cabeçalho) — dizer explicitamente
  -- custa duas linhas e não depende de por que a outra regra funciona.
  if new.space_id is distinct from old.space_id
     or new.user_id is distinct from old.user_id then
    raise exception 'O vínculo não muda de espaço nem de pessoa.'
      using errcode = '42501';
  end if;

  select s.owner_id into _owner from public.spaces s where s.id = old.space_id;

  if old.user_id = _owner then
    if new.role is distinct from old.role then
      raise exception 'Quem criou o espaço é sempre admin.'
        using errcode = '42501';
    end if;
    -- Sem isto, um admin remove o dono, ou o dono sai e deixa um espaço cujo
    -- `owner_id` aponta para quem não está mais nele. Encerrar um espaço é
    -- arquivá-lo, e isso é outra operação.
    if new.status is distinct from old.status then
      raise exception 'Quem criou o espaço não sai: arquive o espaço.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.space_members_guard()
  from anon, authenticated, public;

drop trigger if exists space_members_guard on public.space_members;

create trigger space_members_guard
  before update on public.space_members
  for each row execute function public.space_members_guard();

-- -------------------------------------------------------------------------
-- O terceiro furo, na outra tabela: `spaces_update_admin` deixa um admin
-- reescrever `owner_id` — e o `with check` aprova, porque `has_space_role`
-- continua verdadeiro depois da troca. Ou seja: admin vira dono sozinho.
--
-- Junto vão `space_type` e `privacy_policy`, invariantes que até agora só
-- existiam como comentário no `SpaceFormSheet`. São regras **opostas** de
-- privacidade (PRD §4.2); trocar o tipo de um espaço com histórico mudaria, de
-- trás para frente, o que cada membro enxerga.
--
-- Transferir posse é uma operação que não existe. Quando existir, nasce como
-- RPC — com as duas pontas conferidas — e não como um UPDATE de coluna solta.
-- -------------------------------------------------------------------------
create or replace function public.spaces_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.owner_id is distinct from old.owner_id then
    raise exception 'A posse do espaço não se transfere por edição.'
      using errcode = '42501';
  end if;
  if new.space_type is distinct from old.space_type
     or new.privacy_policy is distinct from old.privacy_policy then
    raise exception 'O tipo do espaço é escolhido na criação e não muda.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.spaces_guard()
  from anon, authenticated, public;

drop trigger if exists spaces_guard on public.spaces;

create trigger spaces_guard
  before update on public.spaces
  for each row execute function public.spaces_guard();
