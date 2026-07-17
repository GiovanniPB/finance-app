# ADR 0005 — Open Finance via Pluggy (pipeline server-side)

- Status: aceito
- Data: 2026-07-17

## Contexto

O app precisa de Open Finance (sincronização automática de contas/transações) e
usa a **Pluggy** como agregador (ver `docs/pluggy-api-reference.md`). A Pluggy tem
um modelo de autenticação em duas camadas: `CLIENT_ID`/`CLIENT_SECRET` e a API Key
(acesso total, server-side) **jamais** podem estar no cliente; só o `connectToken`
efêmero (30 min) é client-side.

## Decisão

**Todo o dado Open Finance entra pelo servidor**, nunca por chamada direta do
cliente à Pluggy. Caminho único:

```
Pluggy → Edge Function → Postgres → PowerSync (WAL) → SQLite local
```

O cliente só interage com a Pluggy pelo **Pluggy Connect Widget**, inicializado
com um `connectToken` obtido de uma Edge Function nossa.

### Componentes (Supabase Edge Functions, Deno/TS)

1. **`pluggy-connect-token`** — invocada pelo cliente autenticado. Server faz
   `POST /auth` (cacheia `apiKey` ≤ 2h) → `POST /connect_token` com
   `clientUserId = auth.uid()` e `webhookUrl`. Retorna `accessToken`. O cliente
   captura `itemId` no `onSuccess` e grava `open_finance_connections`.
2. **`pluggy-webhook`** — endpoint público HTTPS. Valida header secreto + IP
   allowlist (`52.67.145.81`). **Responde 2xx em < 5s** e **enfileira** (pgmq);
   nada de processamento pesado inline (a Pluggy re-tenta até 9x). Dedup por
   `eventId` em `webhook_events`.
3. **`pluggy-sync-worker`** — consome a fila (pgmq/pg_cron). Para eventos de item,
   **sempre** faz `GET /items/{id}` (nunca confia no payload) →
   `GET /accounts?itemId` → `GET /v2/transactions?accountId` (cursor `next`, 500
   por página) → **UPSERT** no Postgres.

### Propriedade de dados (evita conflito com edições do usuário)

- **Colunas da Pluggy** (`amount_minor`, `occurred_at`, `description_raw`,
  `provider_id`): dono é a Pluggy. Ingestão faz
  `ON CONFLICT (account_id, external_id) DO UPDATE SET` **só** nessas colunas.
- **Colunas do usuário** (`category_id`, `is_shared`, override de `description`):
  dono é o cliente. A ingestão **nunca** as sobrescreve.
- Dedup: `provider_id` (conexões reguladas) senão o `id` da transação Pluggy →
  `external_id`, com `unique (account_id, external_id)`.

### Sincronização contínua

- Confiar no **auto-sync 1x/dia** da Pluggy (`nextAutoSyncAt`); reagir a
  `transactions/created|updated|deleted`. **Não** usar `PATCH /items` em cadência
  (limite 20/min/IP).
- `pg_cron` diário: checar `consentExpiresAt` → `sync_status='expired'` → app pede
  re-consentimento (novo `connectToken` com `itemId`).

### Segredos

`CLIENT_ID`/`CLIENT_SECRET` no Supabase Vault / secrets das Edge Functions.
Credenciais bancárias **nunca** transitam por nós (ficam na Pluggy).

## Consequências

- `CLIENT_SECRET` fora do binário do cliente; superfície de ataque no servidor.
- Dado OF surge no cliente pelo mesmo mecanismo reativo (`watch`) de qualquer
  tabela — a UI não distingue origem além do campo `source`.
- Tabelas server-only (`webhook_events`, mirrors raw) ficam **fora** das sync
  rules e sem policy de INSERT para o cliente.
- Plano Free da Pluggy só cria item via widget — o que já é o nosso fluxo.

## Alternativas descartadas

- **Cliente chamando a Pluggy direto**: exporia segredos; proibido.
- **Backend próprio separado**: Edge Functions + pg_cron + pgmq cobrem o caso sem
  introduzir outra infra fora do Supabase.
