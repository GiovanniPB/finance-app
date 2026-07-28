-- =========================================================================
-- A causa real de "criar espaço aparece e some": a policy de **SELECT** não
-- enxergava a linha que estava sendo inserida.
--
-- A migration anterior (20260728203910) mexeu no WITH CHECK de UPDATE a partir
-- de um diagnóstico **errado**, e não resolveu. Esta a substitui. O erro de
-- diagnóstico está registrado de propósito: a hipótese passou por reprodução
-- em SQL e mesmo assim era falsa, porque o teste que a "confirmou" comparava
-- `insert` puro com `on conflict` sem isolar a terceira variável.
--
-- ─────────────────────────────────────────────────────────────────────────
-- A MEDIÇÃO QUE FECHOU O CASO
--
-- Quatro formas do mesmo INSERT, mesma sessão, mesmo payload:
--
--   | forma                                   | resultado |
--   |-----------------------------------------|-----------|
--   | `insert` puro                           | ok        |
--   | `insert … on conflict do nothing`       | 42501     |
--   | `insert … on conflict do update`        | 42501     |
--   | `insert … returning`                    | **42501** |
--
-- O `returning` é o que derruba a hipótese do UPDATE: ele não tem ramo de
-- update nenhum. O que as três formas que falham têm em comum é **precisar ler
-- a linha** — `on conflict` para arbitrar o conflito, `returning` para
-- devolvê-la. Ler engaja a policy de SELECT.
--
-- E a de `spaces` era:
--
--     private.is_space_member(id) or private.is_space_owner(id)
--
-- `is_space_owner(id)` faz `select … from public.spaces where id = _id and
-- owner_id = auth.uid()`. Sendo `stable`, ela enxerga o snapshot do comando —
-- que **não** contém a linha que o próprio comando está inserindo. Resultado:
-- falso, SELECT reprova, e o Postgres responde `42501 new row violates
-- row-level security policy`.
--
-- O PostgREST sempre manda `RETURNING`, então todo insert de espaço vindo do
-- cliente caía aqui. O `SupabaseConnector` descarta o batch em
-- `PostgrestException` (para não travar a fila), o espaço nascia só no SQLite
-- local, e o checkpoint seguinte do PowerSync o apagava — "aparece e some",
-- sem erro na tela.
--
-- ─────────────────────────────────────────────────────────────────────────
-- A CORREÇÃO: PERGUNTAR À COLUNA, NÃO À TABELA
--
-- `private.is_space_owner(id)` e `owner_id = auth.uid()` respondem à **mesma**
-- pergunta. A diferença é que a primeira precisa que a linha já exista e a
-- segunda não — ela lê a coluna da linha que está ali. Trocar uma pela outra
-- não muda quem enxerga o quê; muda **quando** dá para responder.
--
-- De brinde sai mais barato: some uma chamada de função `security definer` e
-- uma subconsulta em `public.spaces` de toda leitura de espaço.
--
-- `is_space_member(id)` fica, porque essa pergunta é sobre outra tabela
-- (`space_members`) e não tem como ser respondida por coluna.
--
-- **A regra que fica para as próximas tabelas:** policy que consulta a própria
-- tabela pelo `id` torna a linha invisível a si mesma no instante do INSERT, e
-- quebra qualquer criação vinda do cliente — porque o PostgREST usa
-- `RETURNING`. Quando a pergunta puder ser respondida por uma coluna da linha,
-- responda por ela.
--
-- Varrendo `pg_policies`, `spaces` era a única tabela com essa forma. As
-- outras já perguntam por coluna (`owner_id = auth.uid()`,
-- `has_space_role(space_id, …)`, `user_id = auth.uid()`) — e é exatamente por
-- isso que criar conta, lançamento, orçamento e meta sempre funcionou.
-- =========================================================================

drop policy if exists "spaces_select_member_or_owner" on public.spaces;

create policy "spaces_select_member_or_owner"
  on public.spaces for select
  using (
    private.is_space_member(id)
    -- Era `private.is_space_owner(id)`. Ver o cabeçalho: mesma pergunta,
    -- respondível na linha que está nascendo.
    or owner_id = auth.uid()
  );

-- Mesma troca no UPDATE, pela mesma razão — e desfazendo o `or owner_id =
-- auth.uid()` que a 20260728203910 havia **acrescentado** ao WITH CHECK: com a
-- substituição, a cláusula extra vira redundante.
drop policy if exists "spaces_update_admin" on public.spaces;

create policy "spaces_update_admin"
  on public.spaces for update
  using (
    private.has_space_role(id, array['admin'])
    or owner_id = auth.uid()
  )
  with check (
    private.has_space_role(id, array['admin'])
    or owner_id = auth.uid()
  );
