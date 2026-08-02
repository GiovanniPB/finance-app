-- =========================================================================
-- nome-de-membro: a linha de membro passa a dizer de quem ela é.
--
-- POR QUE O NOME É DENORMALIZADO AQUI E NÃO LIDO DE `profiles`.
--
-- O caminho óbvio seria um bucket novo nas sync rules entregando o `profiles`
-- de cada peer, com um parameter query juntando `space_members` consigo mesma.
-- Ele não existe: a doc do PowerSync é explícita sobre Sync Rules — "Not
-- supported: subqueries, JOINs, CTEs, aggregation, sorting, or set operations"
-- — e a restrição vale para parameter query e para data query. Sem join,
-- `profiles` é inalcançável por espaço, porque a tabela não tem `space_id`.
--
-- Este repo já tinha resolvido o mesmo problema uma vez: o cabeçalho da
-- `20260727235500` explica por que `savings_contributions.space_id` é
-- denormalizado, com as mesmas palavras ("as sync rules do PowerSync não fazem
-- join"). O padrão é o mesmo aqui: o dado viaja na linha que já está no bucket.
--
-- O QUE ISSO COMPRA, ALÉM DE FUNCIONAR. `by_space` lê `select * from
-- space_members`, e coluna nova em tabela que já está num bucket **não exige
-- republicar as sync rules**. Republicar é passo manual no dashboard e é a
-- armadilha nº 1 deste repo — falha como tela vazia, sem erro nenhum. Esta
-- fatia não a atravessa.
--
-- POR QUE NÃO HÁ POLICY NOVA EM `profiles`. A alternativa exigiria abrir
-- `profiles` para SELECT de quem compartilha espaço — uma superfície nova de
-- leitura sobre a tabela de identidade, com função de apoio nova em `private`.
-- Denormalizando, a visibilidade do nome passa a ser exatamente a de
-- `space_members`: membros ativos dos meus espaços, que é o alvo. `profiles`
-- continua com as três policies `*_own` da `20260714153329`, intactas.
--
-- O CUSTO ACEITO. Dado duplicado, mantido por dois triggers: um que preenche na
-- entrada, outro que propaga quando a pessoa troca o nome. A fonte da verdade
-- continua sendo `profiles.display_name`; `space_members.display_name` é cópia
-- e nunca é escrita pela UI.
--
-- POR QUE A GUARDA DE `space_members` NÃO ATRAPALHA. `space_members_guard`
-- (ver `20260728210321`) barra mudança de `space_id`, de `user_id`, e de `role`
-- ou `status` na linha do dono. A propagação mexe só em `display_name`, então
-- passa — mas passa **pelo** trigger, que continua guardando o resto.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A coluna. Nullable de propósito: quem nunca abriu o Perfil não tem nome, e
-- a UI cai no texto que já existe hoje ("Você", "No espaço desde 12 de julho").
-- Nulo é o estado normal de toda linha até esta fatia rodar.
-- -------------------------------------------------------------------------
alter table public.space_members
  add column if not exists display_name text;

-- -------------------------------------------------------------------------
-- O limite do nome, na fonte da verdade.
--
-- 1–120 é o mesmo `check` de `spaces.name` (`20260717120000`). Vale a pena
-- estar no banco e não só no sheet: o cliente é offline-first e a escrita chega
-- pela fila de upload, onde não há tela para recusar. String vazia é barrada
-- junto — o Dart manda `null`, nunca `''`, e a diferença entre os dois é
-- exatamente a diferença entre "sem nome" e "nome em branco".
--
-- Todo `display_name` existente é nulo (nada no app jamais escreveu a coluna),
-- então a validação não tem o que reprovar.
-- -------------------------------------------------------------------------
alter table public.profiles
  add constraint profiles_display_name_length
  check (display_name is null or char_length(display_name) between 1 and 120);

-- -------------------------------------------------------------------------
-- Backfill. Hoje não move nenhuma linha, porque nenhum perfil tem nome. Existe
-- para a migration ser verdadeira fora daqui: rodada sobre um banco onde
-- alguém já escreveu `profiles.display_name` por fora do app, ela deixa as duas
-- tabelas coerentes em vez de esperar o próximo UPDATE.
-- -------------------------------------------------------------------------
update public.space_members m
   set display_name = p.display_name
  from public.profiles p
 where p.id = m.user_id
   and m.display_name is distinct from p.display_name;

-- -------------------------------------------------------------------------
-- Entrada: a membership nasce com o nome de quem entrou.
--
-- Sem isto, quem já tem nome e entra num espaço novo aparece sem nome até
-- trocar o nome de novo — um estado que ninguém sabe como sair.
--
-- `security definer` porque a função lê `profiles` de dentro de um INSERT feito
-- pelo papel `authenticated`, e a policy `profiles_select_own` esconderia a
-- linha de qualquer pessoa que não seja ela mesma. Hoje quem insere é sempre o
-- próprio usuário (criar espaço, entrar por código), mas depender disso seria
-- depender de um invariante que a RPC de convite pode mudar.
-- -------------------------------------------------------------------------
create or replace function public.space_members_inherit_display_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select p.display_name into new.display_name
  from public.profiles p
  where p.id = new.user_id;

  return new;
end;
$$;

-- Função de trigger não tem por que ser endpoint REST (mesma razão da
-- `20260727235500`: tudo em `public` vira `/rest/v1/rpc/<nome>`). O trigger
-- segue disparando — a permissão é checada na criação dele, não a cada linha.
revoke execute on function public.space_members_inherit_display_name()
  from anon, authenticated, public;

drop trigger if exists space_members_inherit_display_name
  on public.space_members;

create trigger space_members_inherit_display_name
  before insert on public.space_members
  for each row execute function public.space_members_inherit_display_name();

-- -------------------------------------------------------------------------
-- Propagação: trocar o nome no Perfil reescreve toda membership da pessoa.
--
-- `after update of display_name` com `when` no gatilho: sem os dois, todo
-- UPDATE de `profiles` varreria `space_members` à toa. O índice
-- `space_members_user_id_idx` (`20260717120000`) atende o `where`.
--
-- `security definer` é o que faz a linha do peer ser reescrita: sob
-- `security invoker` as policies de UPDATE de `space_members`
-- (`space_members_update_admin` e `space_members_leave_self`) recusariam — a
-- pessoa não é admin do espaço só por ter trocado o próprio nome.
--
-- Não há recursão: `space_members` não escreve em `profiles`.
-- -------------------------------------------------------------------------
create or replace function public.profiles_propagate_display_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.space_members
     set display_name = new.display_name
   where user_id = new.id
     and display_name is distinct from new.display_name;

  return null;
end;
$$;

revoke execute on function public.profiles_propagate_display_name()
  from anon, authenticated, public;

drop trigger if exists profiles_propagate_display_name on public.profiles;

create trigger profiles_propagate_display_name
  after update of display_name on public.profiles
  for each row
  when (new.display_name is distinct from old.display_name)
  execute function public.profiles_propagate_display_name();
