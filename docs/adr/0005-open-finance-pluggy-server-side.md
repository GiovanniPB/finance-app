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

## Revisão de 2026-07-28 (fatia de fundação de schema)

Duas coisas mudam ao sair do desenho para o SQL. A decisão central — todo dado
entra pelo servidor — segue de pé.

### A IP allowlist deixa de ser bloqueante

O texto acima manda validar "header secreto + IP allowlist (`52.67.145.81`)". A
allowlist passa a ser **registro, não recusa**: o header secreto é o que de fato
autentica, e IP de fornecedor muda sem aviso.

O que decidiu foi o **modo de falha**. Com a allowlist bloqueante, uma troca de
IP da Pluggy produz webhooks recusados com 4xx, a Pluggy desiste após 9
tentativas, e a sincronização para **sem erro visível em lugar nenhum** — é
exatamente o modo de falha que este projeto já pagou com as sync rules não
publicadas (tabela vazia no cliente, zero mensagens). Um IP desconhecido com
header válido é mais provavelmente infraestrutura nova do fornecedor que ataque;
e um atacante que tenha o header não é barrado por um IP de origem que ele pode
não precisar forjar.

Fica: header secreto **obrigatório** (sem ele, 401), IP fora da lista **logado**
com aviso e processado.

### O header secreto do webhook **não existe** neste caminho

A revisão acima manteve "header secreto obrigatório". Ao implementar o webhook,
isso se mostrou **impossível**: a referência da Pluggy (§8.5) diz que `headers`
customizados só se configuram ao criar uma **instância de webhook** por
`POST /webhooks`. O nosso `webhookUrl` vai no Connect Token, e por esse caminho a
Pluggy envia o POST **sem header algum**. Exigir o header recusaria 100% dos
webhooks — falha total e silenciosa, precisamente o que a revisão queria evitar.

A autoridade passa a vir de três outros lugares, e nenhum deles depende de quem
chama:

1. **O payload nunca é confiado** — ele diz apenas *que algo mudou, em qual
   item*. Todo dado vem do `GET /items/{id}` autenticado com a nossa apiKey,
   como este ADR já mandava.
2. **Só item que já é nosso é aceito.** `itemId` fora de
   `open_finance_connections` é descartado (com 2xx, para a Pluggy não re-tentar
   nove vezes algo que nunca vamos querer).
3. **`event_id` é `unique`** — reenvio e repetição colidem no banco.

O que resta de exposição é ruído: um terceiro pode disparar re-buscas de itens
que já são nossos. Custa chamada à Pluggy, não vaza dado e não escreve nada que a
Pluggy não confirme. Quando existir uma instância registrada com header, ela
**é** validada — o código aceita os dois mundos, e a variável
`PLUGGY_WEBHOOK_SECRET` liga a exigência.

**Descartado explicitamente: segredo na URL.** Seria o jeito fácil de ter algo
compartilhado neste caminho, e coloca credencial em log de acesso, histórico e
métrica — para proteger um endpoint que, pelas três razões acima, já não é um
vetor de escrita.

### pgmq não entrou; `webhook_events` é a fila

O ADR previa pgmq. Quando o worker foi escrito, a tabela de idempotência já tinha
tudo o que uma fila precisa: `processed_at`, `attempts`, `last_error` e índice
parcial em não-processados. pgmq guardaria **os mesmos fatos num segundo lugar**,
criando duas verdades para reconciliar ("na fila e não no log", "processado no log
e ainda na fila").

O que se perde: visibility timeout e dead-letter. O substituto é `attempts` — ao
esgotar as tentativas, o evento é encerrado com o erro gravado em vez de girar
para sempre. E o que torna a ausência de trava aceitável é **idempotência**: dois
workers no mesmo evento reescrevem as mesmas linhas com os mesmos valores, porque
conta e transação são casadas por id externo.

Se o volume crescer ao ponto de a varredura pesar, pgmq volta à mesa — mas então
como **substituto** da varredura, não como segunda cópia dela.

### `provider_id` e `external_id` viram uma coluna só

O ADR listava as duas. Viraram `transactions.external_id`, porque o próprio
critério de dedup daqui de cima ("`provider_id` senão o `id` da transação") diz
que os dois nunca coexistem: um é o valor preferido do outro. Duas colunas
guardariam o mesmo fato com dois nomes, e a `unique` teria de eleger uma.

Custo aceito: a linha não conta se o id veio de conexão regulada ou de
screen-scraping. Se isso passar a importar, o lugar é uma coluna de
**procedência** (`external_id_source`), não uma segunda cópia do id.

## Alternativas descartadas

- **Cliente chamando a Pluggy direto**: exporia segredos; proibido.
- **Backend próprio separado**: Edge Functions + pg_cron + pgmq cobrem o caso sem
  introduzir outra infra fora do Supabase.
