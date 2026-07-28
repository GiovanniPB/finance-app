-- =========================================================================
-- Fundação do Open Finance: onde a conexão bancária mora, onde o webhook cai,
-- e como um lançamento importado se distingue de um digitado.
--
-- Ver ADR 0005 (pipeline server-side via Pluggy). Esta migration é **só a
-- fundação de schema** — nenhuma Edge Function existe ainda, e nada aqui chama
-- a Pluggy. O que ela garante é que, quando a ingestão existir, ela tenha onde
-- gravar sem inventar coluna no meio do caminho.
--
-- ─────────────────────────────────────────────────────────────────────────
-- 1. A CONEXÃO É DO USUÁRIO, NÃO DO ESPAÇO.
--
-- `open_finance_connections` é escopada por `owner_id`, igual a `accounts` e ao
-- contrário de `transactions`. Três razões: o `clientUserId` que mandamos para a
-- Pluggy é `auth.uid()`, então a conexão nasce amarrada a uma pessoa; o consen-
-- timento do Open Finance é pessoal e intransferível; e quem revoga é o titular.
-- Um household vê as **contas** vinculadas (via `accounts.linked_space_id`), não
-- a credencial que as alimenta. Sync pelo bucket `user_owned`.
--
-- ─────────────────────────────────────────────────────────────────────────
-- 2. DOIS CAMPOS DE STATUS, E ISSO É DE PROPÓSITO.
--
-- `status` é **nosso** vocabulário (poucos valores, estáveis, é o que a UI lê).
-- `provider_execution_status` é o texto **cru** da Pluggy, guardado para
-- diagnóstico. A Pluggy tem mais de uma dúzia de `executionStatus`
-- (`WAITING_USER_INPUT`, `LOGIN_MFA_ERROR`, `OUTDATED`…) e mapear todos para
-- estados de tela produziria uma UI que muda quando o fornecedor renomeia um
-- enum. É a mesma separação de `description` (nossa) e `description_raw` (deles).
--
-- ─────────────────────────────────────────────────────────────────────────
-- 3. `webhook_events` É SERVER-ONLY, E O JEITO DE DIZER ISSO É *NENHUMA POLICY*.
--
-- RLS ligada e zero policies = ninguém que passe pela API alcança a tabela, nem
-- para ler. A Edge Function escreve pela service-role, que ignora RLS. A tabela
-- também fica fora das sync rules: é registro de operação, não dado do usuário.
--
-- Ela **não é uma fila** — é o log que garante idempotência. A Pluggy re-tenta
-- um webhook até 9 vezes, e sem dedup por `event_id` a mesma notificação seria
-- processada nove vezes. A fila de trabalho (pgmq) entra com o worker, na fatia
-- em que houver o que consumir; instalar extensão antes de existir consumidor
-- seria schema sem uso.
--
-- ─────────────────────────────────────────────────────────────────────────
-- 4. UM `external_id`, NÃO DOIS — DESVIO DELIBERADO DO ADR.
--
-- O ADR 0005 lista `provider_id` e `external_id` como colunas separadas. Aqui
-- vira **uma só**, porque o próprio ADR diz que a chave de dedup é
-- "`provider_id` (conexões reguladas) senão o `id` da transação Pluggy" — ou
-- seja, os dois nunca são usados ao mesmo tempo: um é o valor preferido do
-- outro. Duas colunas guardariam o mesmo fato com nomes diferentes, e a `unique`
-- teria de escolher uma delas de qualquer forma.
--
-- O que se perde: saber, olhando a linha, se aquele id veio de conexão regulada
-- ou de screen-scraping. Se isso passar a importar, o lugar é uma coluna que
-- diga *a procedência* (`external_id_source`), não uma segunda cópia do id.
-- Registrado na revisão do ADR 0005.
--
-- ─────────────────────────────────────────────────────────────────────────
-- 5. A `unique` É PARCIAL, E TEM DE SER.
--
-- `unique (account_id, external_id)` sem `where external_id is not null`
-- carregaria no índice todas as linhas manuais — a maioria absoluta da tabela —
-- sem nunca ser usado por elas. (Em Postgres nulos não colidem entre si, então
-- a corretude não dependia disso; o tamanho do índice, sim.)
-- =========================================================================

-- -------------------------------------------------------------------------
-- open_finance_connections: um item da Pluggy = uma instituição conectada.
-- -------------------------------------------------------------------------
create table public.open_finance_connections (
  id                        uuid primary key default gen_random_uuid(),
  owner_id                  uuid not null
                              references auth.users (id) on delete cascade,
  -- O `itemId` da Pluggy. `unique` global: um item pertence a um usuário só, e
  -- se dois usuários reivindicassem o mesmo item, um estaria vendo dado do
  -- outro. Melhor falhar na escrita.
  item_id                   text not null unique
                              check (char_length(item_id) between 1 and 100),
  -- Identidade da instituição, capturada do widget. Guardada em vez de
  -- re-buscada porque a lista de conexões precisa de nome e logo para renderizar
  -- offline — e o nome do banco não muda com frequência.
  connector_id              integer,
  connector_name            text check (char_length(connector_name) <= 120),
  connector_image_url       text,
  -- Nosso vocabulário. `consent_expired` é o único que a UI transforma em
  -- pedido de re-consentimento (ADR 0005, sincronização contínua).
  status                    text not null default 'pending'
                              check (status in (
                                'pending',            -- 1ª sync não terminou
                                'active',
                                'login_error',        -- credencial mudou
                                'waiting_user_input', -- MFA pendente
                                'outdated',           -- Pluggy não atualizou
                                'consent_expired',
                                'deleted'             -- removida na Pluggy
                              )),
  -- Texto cru da Pluggy, para diagnóstico. Sem check: é vocabulário deles.
  provider_execution_status text,
  provider_status_detail    text,
  consent_expires_at        timestamptz,
  last_synced_at            timestamptz,
  next_auto_sync_at         timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index open_finance_connections_owner_id_idx
  on public.open_finance_connections (owner_id);

-- O cron diário de consentimento varre por data; sem isto vira seq scan.
create index open_finance_connections_consent_expires_at_idx
  on public.open_finance_connections (consent_expires_at)
  where consent_expires_at is not null;

create trigger open_finance_connections_set_updated_at
  before update on public.open_finance_connections
  for each row execute function public.set_updated_at();

alter table public.open_finance_connections enable row level security;

-- Só o titular, nas quatro operações. Não há variante de household: a conexão
-- não é compartilhada nem em espaço de transparência total (ver cabeçalho, 1).
create policy "open_finance_connections_select_own"
  on public.open_finance_connections for select
  using (owner_id = auth.uid());

create policy "open_finance_connections_insert_own"
  on public.open_finance_connections for insert
  with check (owner_id = auth.uid());

create policy "open_finance_connections_update_own"
  on public.open_finance_connections for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "open_finance_connections_delete_own"
  on public.open_finance_connections for delete
  using (owner_id = auth.uid());

alter table public.open_finance_connections replica identity full;

-- -------------------------------------------------------------------------
-- webhook_events: log de idempotência do webhook. Server-only.
-- -------------------------------------------------------------------------
create table public.webhook_events (
  id           uuid primary key default gen_random_uuid(),
  -- Chave de dedup. `unique` é o que torna o reenvio da Pluggy inofensivo:
  -- a segunda tentativa colide e é descartada.
  event_id     text not null unique,
  event_type   text not null,
  item_id      text,
  payload      jsonb not null,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  attempts     integer not null default 0,
  last_error   text
);

create index webhook_events_item_id_idx on public.webhook_events (item_id);

-- Fila de trabalho pendente: o worker procura o que ainda não foi processado.
-- Parcial, porque processado é a maioria e nunca é lido por esta query.
create index webhook_events_unprocessed_idx
  on public.webhook_events (received_at)
  where processed_at is null;

-- RLS ligada e **nenhuma policy**: negação total para `anon` e `authenticated`.
-- A Edge Function escreve pela service-role, que ignora RLS por definição.
alter table public.webhook_events enable row level security;

-- A publication `powersync` é FOR ALL TABLES, então esta tabela entra nela
-- queira-se ou não. `replica identity full` evita que um UPDATE aqui vire erro
-- de replicação no PowerSync — ela não é sincronizada (não está em sync rule
-- nenhuma), mas passa pelo mesmo WAL.
alter table public.webhook_events replica identity full;

-- -------------------------------------------------------------------------
-- transactions: de onde o lançamento veio, e como não duplicá-lo.
-- `source` já existia com o check ('manual','open_finance') desde a
-- 20260727151151 — não é preciso criá-lo.
-- -------------------------------------------------------------------------
alter table public.transactions
  add column external_id     text,
  -- Descrição como o banco a escreveu. `description` continua sendo a do
  -- usuário: a ingestão preenche `description_raw` e **nunca** sobrescreve
  -- `description` (ADR 0005, propriedade de dados). Sem isso, renomear um
  -- lançamento importado seria desfeito na próxima sincronização.
  add column description_raw text;

-- Ver o item 5 do cabeçalho: parcial de propósito.
create unique index transactions_account_external_id_key
  on public.transactions (account_id, external_id)
  where external_id is not null;

-- -------------------------------------------------------------------------
-- accounts: qual conexão alimenta esta conta, e qual é o id dela lá.
-- `on delete set null` e não `cascade`: desconectar o banco não pode apagar a
-- conta nem, por tabela abaixo, o histórico de lançamentos dela. O dinheiro
-- passou de verdade; quem terminou foi o vínculo.
-- -------------------------------------------------------------------------
alter table public.accounts
  add column connection_id uuid
    references public.open_finance_connections (id) on delete set null,
  add column external_id   text;

create index accounts_connection_id_idx on public.accounts (connection_id);

-- Duas contas da mesma conexão não podem ser o mesmo `accountId` da Pluggy.
-- Parcial pelo mesmo motivo do índice de `transactions`: conta manual não tem
-- `external_id` e não deve ocupar o índice.
create unique index accounts_connection_external_id_key
  on public.accounts (connection_id, external_id)
  where external_id is not null;
