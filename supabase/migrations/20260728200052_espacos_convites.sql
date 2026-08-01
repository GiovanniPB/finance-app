-- =========================================================================
-- Convites de espaço — a porta de entrada da Fase 2 (PRD §8.1, §12.1).
--
-- ─────────────────────────────────────────────────────────────────────────
-- 1. POR QUE ENTRAR PRECISA DE SERVIDOR, E CRIAR NÃO
--
-- Criar espaço compartilhado é **cliente puro**, e de propósito: a policy
-- `spaces_insert_own` aceita `owner_id = auth.uid()`, e
-- `space_members_insert_owner_or_admin` aceita o dono inserindo a própria
-- linha. As duas escritas nascem locais e sobem pelo PowerSync, então criar um
-- espaço funciona offline como qualquer outro registro do app.
--
-- **Entrar não pode ser cliente.** O convidado não é membro ainda: ele não
-- enxerga o espaço (`spaces_select_member_or_owner`), não enxerga o convite, e
-- a policy de insert em `space_members` exige ser dono ou admin. Afrouxá-la
-- para "qualquer um pode se inserir" transformaria `space_members` numa porta
-- aberta — bastaria adivinhar um uuid de espaço.
--
-- Daí a RPC `join_space_by_code`: `security definer`, com a validação inteira
-- do lado do servidor. É a **única** forma de virar membro sem já ser membro.
--
-- ─────────────────────────────────────────────────────────────────────────
-- 2. RPC EM POSTGRES, NÃO EDGE FUNCTION
--
-- As duas resolveriam. A RPC ganha em três pontos concretos:
--
--  * **sobe por `supabase db push`**, junto do schema de que ela depende — sem
--    um segundo passo de deploy que pode ficar para trás da migration;
--  * roda **dentro** da transação do Postgres, então "achar o convite e inserir
--    o membro" é atômico sem coordenação;
--  * não precisa de segredo nenhum: `auth.uid()` já é quem chamou.
--
-- Edge Function continua sendo o lugar de quem fala com terceiros (Pluggy).
--
-- ─────────────────────────────────────────────────────────────────────────
-- 3. `space_invites` NÃO É SINCRONIZADA
--
-- A tabela fica fora das sync rules **por escolha**, e isso evita republicar o
-- arquivo no dashboard do PowerSync (passo manual, e a causa conhecida de
-- "tela vazia sem erro" neste projeto).
--
-- Dá para deixar de fora porque convite não tem uso offline: o código só vale
-- se a outra pessoa estiver online para resgatá-lo. O app lê o código pela RPC
-- `space_invite_code`, que é idempotente — devolve o convite vigente e só cria
-- um quando não há.
--
-- ─────────────────────────────────────────────────────────────────────────
-- 4. O CÓDIGO EVITA AMBIGUIDADE VISUAL, E POR ISSO NÃO É BASE64
--
-- O código é lido em voz alta e digitado à mão, e cada símbolo confundível vira
-- uma tentativa falha que parece "o convite não funciona". O alfabeto derruba
-- `0`, `1`, `I`, `L`, `O` e `S`: de cada confusão clássica sobra no máximo um
-- símbolo — `0`/`O` saem os dois, `1`/`I`/`L` saem os três, e de `5`/`S` fica
-- só o `5`.
--
-- Sobram 30 símbolos, e oito caracteres dão ~6,6·10¹¹ combinações, com
-- expiração de 7 dias e unicidade garantida por constraint.
--
-- O `check` da coluna é `^[A-Z2-9]{8}$`, **mais largo** que esse alfabeto de
-- propósito: ele é guarda de sanidade contra lixo, não a definição do
-- alfabeto — que vive em `private.generate_invite_code`, o único escritor.
-- =========================================================================

-- -------------------------------------------------------------------------
-- space_invites
-- -------------------------------------------------------------------------
create table public.space_invites (
  id         uuid primary key default gen_random_uuid(),
  space_id   uuid not null references public.spaces (id) on delete cascade,
  code       text not null unique check (code ~ '^[A-Z2-9]{8}$'),
  -- O papel que quem entrar recebe. `viewer` fica de fora: um convite que dá
  -- só leitura é caso de uso de gestão de membro, não de porta de entrada, e
  -- oferecê-lo aqui convidaria a criar membro que não pode lançar nada.
  role       text not null default 'editor'
               check (role in ('admin', 'editor')),
  created_by uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '7 days',
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

-- A busca por código é servida pelo índice de unicidade. Este outro é o
-- "convite vigente deste espaço", que `space_invite_code` faz a cada abertura
-- da folha de convite.
create index space_invites_space_idx
  on public.space_invites (space_id)
  where revoked_at is null;

-- -------------------------------------------------------------------------
-- Geração de código no alfabeto sem ambiguidade (item 4).
--
-- Vive em `private` porque não é endpoint: é apoio de `space_invite_code`.
-- -------------------------------------------------------------------------
create or replace function private.generate_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  _alphabet constant text := 'ABCDEFGHJKMNPQRTUVWXYZ23456789';
  _code text := '';
begin
  for _i in 1..8 loop
    _code := _code || substr(
      _alphabet,
      1 + floor(random() * length(_alphabet))::int,
      1
    );
  end loop;
  return _code;
end;
$$;

-- -------------------------------------------------------------------------
-- RPC: o código vigente do espaço, criando um se não houver.
--
-- Idempotente de propósito. A folha de convite pode ser aberta e fechada
-- quantas vezes for, e o código mostrado é o mesmo enquanto valer — um código
-- novo a cada abertura invalidaria o que a pessoa acabou de mandar no WhatsApp.
-- -------------------------------------------------------------------------
create or replace function public.space_invite_code(_space_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  _code text;
begin
  -- `security definer` ignora RLS, então a autorização é explícita aqui.
  -- Só admin convida (matriz do PRD §7).
  if not (
    private.has_space_role(_space_id, array['admin'])
    or private.is_space_owner(_space_id)
  ) then
    raise exception 'Sem permissão para convidar neste espaço'
      using errcode = '42501';
  end if;

  if exists (
    select 1 from public.spaces s
    where s.id = _space_id and s.status <> 'active'
  ) then
    raise exception 'Espaço arquivado não recebe novos membros'
      using errcode = '22023';
  end if;

  select i.code into _code
  from public.space_invites i
  where i.space_id = _space_id
    and i.revoked_at is null
    and i.expires_at > now()
  order by i.created_at desc
  limit 1;

  if _code is not null then
    return _code;
  end if;

  -- Laço porque `code` é unique: colisão em 30^8 é improvável e não impossível,
  -- e um erro aqui seria "convidar não funciona" sem explicação.
  for _attempt in 1..10 loop
    begin
      insert into public.space_invites (space_id, code, created_by)
      values (_space_id, private.generate_invite_code(), auth.uid())
      returning code into _code;
      return _code;
    exception when unique_violation then
      -- tenta de novo com outro código
    end;
  end loop;

  raise exception 'Não foi possível gerar um código de convite';
end;
$$;

-- -------------------------------------------------------------------------
-- RPC: entrar num espaço com o código.
--
-- Devolve o `space_id`, que é o que o app precisa para trocar de contexto.
-- -------------------------------------------------------------------------
create or replace function public.join_space_by_code(_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  _invite public.space_invites;
  _existing public.space_members;
begin
  if auth.uid() is null then
    raise exception 'Sem sessão' using errcode = '42501';
  end if;

  -- Normaliza o que foi digitado: o alfabeto é maiúsculo, e recusar "ab3x" por
  -- causa da caixa seria recusar o código certo.
  select * into _invite
  from public.space_invites i
  where i.code = upper(btrim(_code));

  -- Mensagem única para inexistente, revogado e vencido, de propósito:
  -- distinguir os três diria a quem sonda códigos que acertou o código e errou
  -- só o prazo.
  if _invite.id is null
     or _invite.revoked_at is not null
     or _invite.expires_at <= now() then
    raise exception 'Código inválido ou expirado' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.spaces s
    where s.id = _invite.space_id and s.status <> 'active'
  ) then
    raise exception 'Este espaço foi arquivado' using errcode = '22023';
  end if;

  select * into _existing
  from public.space_members m
  where m.space_id = _invite.space_id and m.user_id = auth.uid();

  -- Já é membro: devolve o espaço em vez de estourar. Reusar o código é o que
  -- acontece quando a pessoa toca no convite duas vezes, e isso não é erro.
  if _existing.id is not null and _existing.status = 'active' then
    return _invite.space_id;
  end if;

  -- Quem saiu e voltou reativa a própria linha: a `unique (space_id, user_id)`
  -- impede uma segunda.
  if _existing.id is not null then
    update public.space_members
    set status = 'active', role = _invite.role, joined_at = now()
    where id = _existing.id;
    return _invite.space_id;
  end if;

  insert into public.space_members (space_id, user_id, role, status)
  values (_invite.space_id, auth.uid(), _invite.role, 'active');

  return _invite.space_id;
end;
$$;

-- -------------------------------------------------------------------------
-- Exposição: as duas RPCs são endpoint de verdade, e por isso ficam em
-- `public` e são chamáveis por `authenticated` — diferente das funções de
-- apoio de RLS, que vivem em `private` justamente para não virarem endpoint
-- (ver a migration 20260728030625).
--
-- `anon` é revogado nas duas: ambas dependem de `auth.uid()`, e sem sessão não
-- há o que fazer além de sondar códigos.
--
-- ⚠️ **O advisor aponta as duas como WARN**
-- (`authenticated_security_definer_function_executable`), e é o resultado
-- pretendido: uma RPC que existe para atravessar a RLS é, por definição,
-- `security definer` chamável por quem ainda não é membro. Mover isso para uma
-- Edge Function calaria o aviso sem mudar o poder concedido — e ainda exigiria
-- a service-role key, que é mais poder, não menos. A autorização está **dentro**
-- das duas: `space_invite_code` exige admin, `join_space_by_code` exige convite
-- vigente.
--
-- O risco residual é **força bruta de código** em `join_space_by_code`, que
-- qualquer usuário autenticado pode chamar em laço. Hoje o que protege são os
-- ~6,6·10¹¹ códigos possíveis e a expiração de 7 dias; **não há rate limit**.
-- Está anotado como débito em `docs/state.md`.
-- -------------------------------------------------------------------------
revoke execute on function private.generate_invite_code()
  from anon, authenticated, public;

revoke execute on function public.space_invite_code(uuid)
  from anon, public;
grant execute on function public.space_invite_code(uuid) to authenticated;

revoke execute on function public.join_space_by_code(text)
  from anon, public;
grant execute on function public.join_space_by_code(text) to authenticated;

-- -------------------------------------------------------------------------
-- RLS: `space_invites` é lida só pelas RPCs (`security definer`), então a
-- tabela fica com RLS ligada e **zero policies**.
--
-- É o mesmo desenho de `webhook_events`: RLS sem policy é como se diz
-- "server-only". O advisor aponta isso como INFO (`rls_enabled_no_policy`), e
-- é o resultado pretendido — não adicione policy para calá-lo.
-- -------------------------------------------------------------------------
alter table public.space_invites enable row level security;

alter table public.space_invites replica identity full;
