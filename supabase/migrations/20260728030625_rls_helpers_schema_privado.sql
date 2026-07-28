-- =========================================================================
-- Tira as funções de autorização do schema exposto pela API.
--
-- O PROBLEMA QUE ISTO RESOLVE. `get_advisors` de 2026-07-28 devolveu nove WARN,
-- e oito eram a mesma coisa dita de duas formas: quatro funções
-- `SECURITY DEFINER` chamáveis por `anon` **e** por `authenticated` via
-- `/rest/v1/rpc/…`. Toda função no schema `public` com `EXECUTE` para esses
-- papéis vira endpoint REST — o PostgREST não distingue "função de apoio" de
-- "função de API", e `supabase/config.toml` expõe `public` e `graphql_public`.
--
-- A severidade era baixa mas não nula. Para `anon`, `auth.uid()` é nulo e as
-- três funções de espaço devolvem falso. Um autenticado, porém, conseguia
-- sondar `is_space_member('<uuid arbitrário>')` e descobrir se é membro de um
-- espaço que não pediu — um oráculo de pertencimento que a UI nunca oferece.
--
-- POR QUE DUAS SAÍDAS DIFERENTES PARA O MESMO AVISO. O linter oferece três
-- remediações (revogar `EXECUTE`, virar `SECURITY INVOKER`, tirar do schema
-- exposto) e a escolha depende de **quem chama a função**:
--
--  * `handle_new_user` é chamada por um trigger em `auth.users`. Trigger roda
--    pelo mecanismo do Postgres, não pelo papel que consulta, então revogar
--    `EXECUTE` de `anon`/`authenticated` não tira nada de ninguém. Este repo já
--    tem a prova: a `20260727235500` revogou `EXECUTE` de
--    `savings_contributions_inherit_space` — também `SECURITY DEFINER`, também
--    de trigger — e o advisor de hoje **não** a lista, com as contribuições
--    continuando a subir para o Postgres pelo papel `authenticated`.
--
--  * `is_space_member`, `has_space_role` e `is_space_owner` são chamadas de
--    dentro de ~28 policies de RLS, em sete tabelas. Aqui as duas primeiras
--    saídas são arriscadas: `SECURITY INVOKER` reintroduz a recursão de
--    `space_members` consultando a si mesma (a razão de elas existirem, ADR
--    0004), e revogar `EXECUTE` arrisca fazer *toda* leitura do app falhar caso
--    a avaliação da policy checque o ACL da função contra o papel da sessão.
--    Sobra a terceira: sair do schema exposto. Os docs do Supabase são
--    explícitos sobre funções de apoio de RLS — não deveriam morar num schema
--    de API.
--
-- POR QUE `alter function … set schema` E NÃO `drop` + `create`. As referências
-- de policy e de trigger são gravadas por **OID**, não por nome: `pg_policy`
-- guarda a expressão já analisada. Mover o schema preserva o OID, então as ~28
-- policies e o trigger de `auth.users` seguem apontando para a mesma função sem
-- serem recriados. Recriar as policies uma a uma seria um diff de trezentas
-- linhas para um resultado idêntico, e cada policy reescrita é uma chance nova
-- de errar um `using` de tabela sensível.
--
-- POR QUE AINDA HÁ `grant` DEPOIS DE MOVER. O que fecha a porta é o schema não
-- estar em `config.toml`; o `grant` abaixo é deliberado e não a reabre — o
-- PostgREST só roteia `/rest/v1/rpc/` para os schemas que expõe, e `private`
-- não é um deles. Conceder explicitamente evita depender de uma pergunta que
-- não se responde sem um Postgres na mão: se a avaliação de uma policy checa
-- `EXECUTE` contra o papel da sessão. Com o grant, a resposta deixa de
-- importar — nos dois mundos a RLS continua funcionando.
--
-- REGRA PARA AS PRÓXIMAS FATIAS: policy nova chama `private.is_space_member` e
-- `private.has_space_role`, não `public.…`. Está registrado no `CLAUDE.md`.
-- =========================================================================

-- -------------------------------------------------------------------------
-- O schema. `authenticated` e `anon` precisam de USAGE para que a avaliação
-- das policies alcance as funções; ninguém precisa de CREATE aqui.
-- -------------------------------------------------------------------------
create schema if not exists private;

revoke all on schema private from anon, authenticated, public;
grant usage on schema private to anon, authenticated;

-- -------------------------------------------------------------------------
-- As três funções de autorização saem de `public`. O `if exists` deixa a
-- migration idempotente: rodando sobre um banco que já as tem em `private`
-- (a nuvem, depois do push), cada bloco simplesmente não faz nada.
-- -------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_space_member'
  ) then
    alter function public.is_space_member(uuid) set schema private;
  end if;

  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'has_space_role'
  ) then
    alter function public.has_space_role(uuid, text[]) set schema private;
  end if;

  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_space_owner'
  ) then
    alter function public.is_space_owner(uuid) set schema private;
  end if;
end;
$$;

grant execute on function private.is_space_member(uuid) to anon, authenticated;
grant execute on function private.has_space_role(uuid, text[]) to anon, authenticated;
grant execute on function private.is_space_owner(uuid) to anon, authenticated;

-- -------------------------------------------------------------------------
-- `handle_new_user`: só o trigger a chama, então o revoke basta. Fica em
-- `public` porque um trigger em `auth.users` não se beneficia da mudança de
-- schema, e mover o que não precisa ser movido é diff sem resultado.
-- -------------------------------------------------------------------------
revoke execute on function public.handle_new_user()
  from anon, authenticated, public;

-- -------------------------------------------------------------------------
-- `set_updated_at`: o nono WARN, e o único que não é sobre exposição.
-- `search_path` mutável numa função de trigger significa que um schema
-- injetado na frente do `public` poderia resolver um nome para outra coisa. Ela
-- não é `SECURITY DEFINER` (roda com os privilégios de quem escreve, então não
-- eleva ninguém) e não é chamável por REST — o PostgREST não expõe função que
-- retorna `trigger`. Por isso não há revoke aqui, só o pino que as funções mais
-- novas já têm. O corpo não referencia objeto nenhum, então `''` basta.
-- -------------------------------------------------------------------------
alter function public.set_updated_at() set search_path = '';
