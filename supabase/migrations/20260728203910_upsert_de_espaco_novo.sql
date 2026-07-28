-- =========================================================================
-- Criar espaço no app aparecia e sumia. A causa é o upsert do PowerSync
-- encontrando uma policy de UPDATE que a linha nova não tem como satisfazer.
--
-- ─────────────────────────────────────────────────────────────────────────
-- O QUE ACONTECIA, MEDIDO
--
-- O `SupabaseConnector` sobe **todo** write local como `upsert` — nunca
-- `insert` puro —, porque um `put` do PowerSync pode ser reenvio depois de
-- reconectar. Em SQL isso é `INSERT … ON CONFLICT (id) DO UPDATE`.
--
-- E o Postgres, nesse comando, aplica o `WITH CHECK` da policy de **UPDATE**
-- além do de INSERT. O de `spaces` era:
--
--     private.has_space_role(id, array['admin']) or private.is_space_owner(id)
--
-- As duas funções **consultam a linha pelo `id`**. Numa linha que ainda não
-- existe as duas devolvem falso, o WITH CHECK reprova, e o Postgres responde
-- `42501 new row violates row-level security policy`.
--
-- O `SupabaseConnector` trata `PostgrestException` descartando o batch (para
-- não travar a fila para sempre) — então o espaço nascia no SQLite local,
-- aparecia na tela, o upload era recusado, e o próximo checkpoint do PowerSync
-- apagava a linha. Daí "aparece e já some", sem erro nenhum na interface.
--
-- Medido no banco: `insert` puro passava, `insert … on conflict do update`
-- reprovava — com o mesmo payload, o mesmo usuário e a mesma sessão.
--
-- ─────────────────────────────────────────────────────────────────────────
-- POR QUE SÓ `spaces` QUEBROU
--
-- Varrendo `pg_policies`, `spaces` é a **única** tabela cujo WITH CHECK de
-- UPDATE pergunta "eu já sou dono/admin desta linha?". Todas as outras se
-- resolvem com colunas da própria linha — `owner_id = auth.uid()`,
-- `has_space_role(space_id, …)`, `user_id = auth.uid()` —, e por isso criar
-- conta, lançamento, orçamento e meta sempre funcionou.
--
-- **A regra que fica para as próximas tabelas:** num app que sincroniza por
-- upsert, o `WITH CHECK` de UPDATE precisa ser avaliável **sobre a linha
-- nova**, sem depender de ela já existir. Policy que consulta a própria linha
-- pelo `id` é incompatível com criação vinda do cliente.
--
-- ─────────────────────────────────────────────────────────────────────────
-- A CORREÇÃO, E O QUE ELA NÃO AFROUXA
--
-- Acrescenta `owner_id = auth.uid()` ao WITH CHECK — uma coluna da própria
-- linha, que a linha nova responde.
--
-- O `USING` fica **intacto**: continua sendo admin-ou-dono quem pode mirar uma
-- linha existente. Ou seja, não-membro segue sem conseguir atualizar espaço
-- nenhum; o que muda é só qual **resultado** é aceito, e "o espaço fica com
-- `owner_id` igual a quem escreveu" é exatamente o que `spaces_insert_own` já
-- permitia.
--
-- Não abre roubo de posse: um admin não-dono já podia gravar qualquer
-- `owner_id`, porque o `has_space_role(id, ['admin'])` do WITH CHECK passava
-- independentemente do valor da coluna.
-- =========================================================================

drop policy if exists "spaces_update_admin" on public.spaces;

create policy "spaces_update_admin"
  on public.spaces for update
  using (
    private.has_space_role(id, array['admin'])
    or private.is_space_owner(id)
  )
  with check (
    private.has_space_role(id, array['admin'])
    or private.is_space_owner(id)
    -- A cláusula que torna a linha nova avaliável. Ver o cabeçalho.
    or owner_id = auth.uid()
  );
