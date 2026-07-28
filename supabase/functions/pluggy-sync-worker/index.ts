// =========================================================================
// pluggy-sync-worker — consome `webhook_events` e traz o dado da Pluggy.
//
// Ver ADR 0005. Caminho: `GET /items/{id}` → `GET /accounts?itemId` →
// `GET /v2/transactions?accountId` (cursor) → escrita no Postgres.
//
// ─────────────────────────────────────────────────────────────────────────
// 1. `webhook_events` É A FILA, E pgmq NÃO ENTROU
//
// O ADR previa pgmq. Ao implementar, a tabela de idempotência já tinha tudo o
// que uma fila precisa: `processed_at`, `attempts`, `last_error` e um índice
// parcial em não-processados. pgmq guardaria **os mesmos fatos num segundo
// lugar**, e aí passariam a existir duas verdades para reconciliar ("está na
// fila mas não no log", "processado no log e ainda na fila"). Para o volume
// deste app — alguns eventos por usuário por dia — um índice parcial resolve.
//
// O que se perde de pgmq: visibility timeout e dead-letter. O substituto é
// `attempts`: passado [MAX_ATTEMPTS], o evento é marcado como processado com o
// erro registrado, para não girar para sempre.
//
// ─────────────────────────────────────────────────────────────────────────
// 2. NÃO HÁ TRAVA, E O QUE PROTEGE É IDEMPOTÊNCIA
//
// Duas execuções simultâneas podem pegar o mesmo evento (não há
// `FOR UPDATE SKIP LOCKED` aqui). Isso é aceitável porque **reprocessar é
// inofensivo**: conta e transação são casadas por id externo, e o segundo passe
// atualiza as mesmas linhas com os mesmos valores. O custo é chamada repetida à
// Pluggy, não dado duplicado.
//
// ─────────────────────────────────────────────────────────────────────────
// 3. PROPRIEDADE DE COLUNA: POR QUE NÃO SE USA `upsert`
//
// O `upsert` do supabase-js manda todas as colunas do payload no `DO UPDATE`.
// Isso apagaria `category_id` e a `description` que o usuário editou a cada
// sincronização — exatamente o que o ADR proíbe. Então a escrita é em duas
// etapas: descobre-se o que já existe por `external_id` e, para essas linhas, o
// UPDATE carrega **só** colunas da Pluggy. `description` é escrita **apenas no
// INSERT**; depois disso ela é do usuário.
//
// ─────────────────────────────────────────────────────────────────────────
// 4. O QUE ESTA FATIA NÃO FAZ
//
//  * `transactions/deleted` — a Pluggy apaga transação depois de merge. Aqui o
//    evento é registrado e **não** apaga nada: apagar lançamento que o usuário
//    já categorizou (ou vinculou a uma meta) exige decisão de produto.
//  * `PENDING` — transação autorizada e não liquidada é ignorada. Não há coluna
//    para marcá-la, e mostrá-la como liquidada faria o saldo mentir.
//  * Investimentos, identidade e pagamentos.
// =========================================================================

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  type CursorPage,
  getApiKey,
  type PluggyAccount,
  type PluggyItem,
  type PluggyTransaction,
  pluggyGet,
  requiredEnv,
} from '../_shared/pluggy.ts';

/// Quantos eventos uma execução processa. Baixo de propósito: o webhook aciona
/// o worker a cada evento, então a fila raramente acumula — e um lote grande
/// aumentaria a chance de estourar o tempo da função.
const EVENT_BATCH = 10;

/// Depois disso o evento é encerrado com o erro registrado, em vez de girar
/// para sempre. É o substituto do dead-letter do pgmq.
const MAX_ATTEMPTS = 5;

/// Páginas de transação por conta numa execução. Guarda contra conta com
/// histórico enorme consumir o tempo da função inteiro; o que sobrar volta na
/// próxima passada, porque o cursor recomeça do `dateFrom` implícito.
const MAX_TRANSACTION_PAGES = 20;

interface WebhookEventRow {
  id: string;
  event_id: string;
  event_type: string;
  item_id: string | null;
  attempts: number;
}

interface ConnectionRow {
  id: string;
  owner_id: string;
  item_id: string;
}

/// Traduz o estado da Pluggy para o nosso vocabulário curto (o que a UI lê).
///
/// A ordem importa: `executionStatus` é mais específico que `status`, então ele
/// decide primeiro. Estado que não reconhecemos vira `pending` em vez de um
/// palpite — a UI mostra "Sincronizando", que é honesto para "não sei ainda".
function mapConnectionStatus(item: PluggyItem): string {
  switch (item.executionStatus) {
    case 'LOGIN_ERROR':
    case 'INVALID_CREDENTIALS':
    case 'INVALID_CREDENTIALS_MFA':
    case 'ACCOUNT_LOCKED':
      return 'login_error';
    case 'WAITING_USER_INPUT':
    case 'WAITING_USER_ACTION':
      return 'waiting_user_input';
    case 'USER_AUTHORIZATION_PENDING':
      return 'waiting_user_input';
    case 'SUCCESS':
    case 'PARTIAL_SUCCESS':
      return 'active';
    case 'ERROR':
    case 'SITE_NOT_AVAILABLE':
    case 'CONNECTION_ERROR':
      return 'outdated';
  }
  switch (item.status) {
    case 'UPDATED':
      return 'active';
    case 'LOGIN_ERROR':
      return 'login_error';
    case 'WAITING_USER_INPUT':
      return 'waiting_user_input';
    case 'OUTDATED':
      return 'outdated';
    case 'UPDATING':
      return 'pending';
  }
  return 'pending';
}

/// Subtipo da Pluggy → nosso `account_type`.
///
/// O conjunto do domínio foi escolhido para este mapeamento ser total (ver
/// `AccountType`): os três subtipos que ela entrega têm correspondente exato.
function mapAccountType(account: PluggyAccount): string {
  switch (account.subtype) {
    case 'CHECKING_ACCOUNT':
      return 'checking';
    case 'SAVINGS_ACCOUNT':
      return 'savings';
    case 'CREDIT_CARD':
      return 'credit_card';
  }
  // Sem subtipo, `type` ainda distingue conta de cartão.
  return account.type === 'CREDIT' ? 'credit_card' : 'other';
}

/// Converte valor decimal em unidades mínimas (ADR 0006: dinheiro é inteiro).
///
/// `Math.round` e não truncamento: `45.99 * 100` dá `4598.9999…` em ponto
/// flutuante, e truncar transformaria R$ 45,99 em R$ 45,98 — erro de um centavo
/// por linha, que soma.
///
/// O valor absoluto é deliberado: a coluna é positiva por constraint e a direção
/// vem de `type`, como em todo o resto do app.
function toMinor(amount: number | undefined): number | null {
  if (typeof amount !== 'number' || !Number.isFinite(amount)) return null;
  const minor = Math.round(Math.abs(amount) * 100);
  return minor > 0 ? minor : null;
}

function isoOrNull(value: string | null | undefined): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

/**
 * Espaço onde o lançamento importado nasce.
 *
 * `transactions.space_id` é `not null`, e a conta de Open Finance pertence ao
 * **dono**, não a um espaço. O destino é o espaço **pessoal** dele — o criado no
 * signup. Não é o "espaço ativo" da sessão de propósito: dado importado não deve
 * depender de qual aba o usuário tinha aberto quando o webhook chegou, senão o
 * mesmo extrato cairia em lugares diferentes a cada sincronização.
 */
async function personalSpaceId(
  supabase: SupabaseClient,
  ownerId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from('spaces')
    .select('id')
    .eq('owner_id', ownerId)
    .eq('space_type', 'personal')
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error('Falha ao resolver o espaço pessoal', error);
    return null;
  }
  return data?.id ?? null;
}

/** Atualiza a conexão com o estado autoritativo do item. */
async function syncConnection(
  supabase: SupabaseClient,
  connection: ConnectionRow,
  item: PluggyItem,
): Promise<void> {
  const { error } = await supabase
    .from('open_finance_connections')
    .update({
      status: mapConnectionStatus(item),
      provider_execution_status: item.executionStatus ?? null,
      provider_status_detail: item.error?.code ?? null,
      consent_expires_at: isoOrNull(item.consentExpiresAt),
      last_synced_at: isoOrNull(item.lastUpdatedAt) ?? new Date().toISOString(),
      next_auto_sync_at: isoOrNull(item.nextAutoSyncAt),
      // O nome do conector pode ter chegado vazio do widget; a API é a fonte
      // melhor. Nunca o apaga: só preenche quando a API tem algo.
      ...(item.connector?.name ? { connector_name: item.connector.name } : {}),
      ...(item.connector?.id ? { connector_id: item.connector.id } : {}),
      ...(item.connector?.imageUrl
        ? { connector_image_url: item.connector.imageUrl }
        : {}),
    })
    .eq('id', connection.id);

  if (error) console.error('Falha ao atualizar a conexão', error);
}

/**
 * Traz as contas do item. Devolve o mapa `id da Pluggy → id da nossa conta`,
 * que a sincronização de transação usa.
 */
async function syncAccounts(
  supabase: SupabaseClient,
  connection: ConnectionRow,
  apiKey: string,
): Promise<Map<string, string>> {
  const byExternalId = new Map<string, string>();

  const page = await pluggyGet<{ results?: PluggyAccount[] }>(
    `/accounts?itemId=${encodeURIComponent(connection.item_id)}`,
    apiKey,
  );
  const accounts = page.results ?? [];
  if (accounts.length === 0) return byExternalId;

  const { data: existing, error: readError } = await supabase
    .from('accounts')
    .select('id, external_id')
    .eq('connection_id', connection.id);

  if (readError) {
    console.error('Falha ao ler as contas existentes', readError);
    return byExternalId;
  }
  const existingByExternal = new Map<string, string>(
    (existing ?? [])
      .filter((row) => typeof row.external_id === 'string')
      .map((row) => [row.external_id as string, row.id as string]),
  );

  const now = new Date().toISOString();

  for (const account of accounts) {
    const balanceMinor = toMinor(account.balance) ?? 0;
    const name = account.marketingName?.trim() || account.name?.trim()
      || 'Conta importada';
    const known = existingByExternal.get(account.id);

    if (known) {
      // Colunas da Pluggy só. `name` fica de fora: renomear a conta é do
      // usuário, e sobrescrever apagaria a escolha dele a cada sincronização.
      const { error } = await supabase
        .from('accounts')
        .update({
          account_type: mapAccountType(account),
          currency: account.currencyCode ?? 'BRL',
          current_balance_minor: balanceMinor,
          balance_as_of: now,
        })
        .eq('id', known);
      if (error) console.error('Falha ao atualizar conta importada', error);
      byExternalId.set(account.id, known);
      continue;
    }

    const { data: inserted, error } = await supabase
      .from('accounts')
      .insert({
        owner_id: connection.owner_id,
        name,
        account_type: mapAccountType(account),
        currency: account.currencyCode ?? 'BRL',
        current_balance_minor: balanceMinor,
        balance_as_of: now,
        connection_id: connection.id,
        external_id: account.id,
      })
      .select('id')
      .maybeSingle();

    if (error) {
      console.error('Falha ao inserir conta importada', error);
      continue;
    }
    if (inserted?.id) byExternalId.set(account.id, inserted.id as string);
  }

  return byExternalId;
}

/** Traz as transações de uma conta, paginando pelo cursor. */
async function syncTransactions(
  supabase: SupabaseClient,
  connection: ConnectionRow,
  apiKey: string,
  externalAccountId: string,
  accountId: string,
  spaceId: string,
): Promise<number> {
  let path: string | null =
    `/v2/transactions?accountId=${encodeURIComponent(externalAccountId)}`;
  let pages = 0;
  let written = 0;

  while (path && pages < MAX_TRANSACTION_PAGES) {
    const page: CursorPage<PluggyTransaction> = await pluggyGet<
      CursorPage<PluggyTransaction>
    >(path, apiKey);
    pages += 1;

    const transactions = (page.results ?? []).filter(
      // `PENDING` fica de fora: ver o item 4 do cabeçalho.
      (transaction) => transaction.status !== 'PENDING',
    );

    if (transactions.length > 0) {
      written += await writeTransactions(
        supabase,
        transactions,
        connection,
        accountId,
        spaceId,
      );
    }

    // O cursor volta como query relativa (`?accountId=...&after=...`); o
    // `pluggyGet` aceita caminho ou URL, mas a query solta precisa do caminho.
    const next = page.next;
    path = next ? (next.startsWith('?') ? `/v2/transactions${next}` : next)
      : null;
  }

  if (path) {
    console.warn('Limite de páginas atingido; o resto vem na próxima passada', {
      accountId,
      pages,
    });
  }

  return written;
}

/**
 * Grava um lote de transações respeitando a propriedade de coluna.
 *
 * Ver o item 3 do cabeçalho: nada de `upsert`. O UPDATE das linhas conhecidas
 * carrega só colunas da Pluggy; `description` e `category_id` nunca aparecem
 * nele.
 */
async function writeTransactions(
  supabase: SupabaseClient,
  transactions: PluggyTransaction[],
  connection: ConnectionRow,
  accountId: string,
  spaceId: string,
): Promise<number> {
  // `providerId` é preferido quando existe (conexão regulada): ele é o mesmo
  // para a mesma transação em items diferentes, então sobrevive a reconectar o
  // banco. Ver o item 4 do cabeçalho da migration 20260728033219.
  const keyed = transactions
    .map((transaction) => ({
      transaction,
      externalId: transaction.providerId?.trim() || transaction.id,
      amountMinor: toMinor(transaction.amount),
      occurredAt: isoOrNull(transaction.date),
    }))
    .filter((entry) => entry.amountMinor !== null && entry.occurredAt !== null);

  if (keyed.length === 0) return 0;

  const { data: existing, error: readError } = await supabase
    .from('transactions')
    .select('id, external_id')
    .eq('account_id', accountId)
    .in('external_id', keyed.map((entry) => entry.externalId));

  if (readError) {
    console.error('Falha ao ler transações existentes', readError);
    return 0;
  }
  const existingByExternal = new Map<string, string>(
    (existing ?? [])
      .filter((row) => typeof row.external_id === 'string')
      .map((row) => [row.external_id as string, row.id as string]),
  );

  const toInsert: Record<string, unknown>[] = [];
  let updated = 0;

  for (const entry of keyed) {
    const { transaction, externalId, amountMinor, occurredAt } = entry;
    const known = existingByExternal.get(externalId);
    const descriptionRaw = transaction.descriptionRaw?.trim()
      || transaction.description?.trim() || null;

    if (known) {
      const { error } = await supabase
        .from('transactions')
        .update({
          amount_minor: amountMinor,
          currency: transaction.currencyCode ?? 'BRL',
          occurred_at: occurredAt,
          type: transaction.type === 'CREDIT' ? 'income' : 'expense',
          description_raw: descriptionRaw,
        })
        .eq('id', known);
      if (error) {
        console.error('Falha ao atualizar transação importada', error);
      } else {
        updated += 1;
      }
      continue;
    }

    toInsert.push({
      space_id: spaceId,
      account_id: accountId,
      created_by: connection.owner_id,
      // `DEBIT`/`CREDIT` da Pluggy já vem normalizado pela ótica do titular —
      // em cartão, compra é DEBIT e pagamento de fatura é CREDIT (§7.4).
      type: transaction.type === 'CREDIT' ? 'income' : 'expense',
      amount_minor: amountMinor,
      currency: transaction.currencyCode ?? 'BRL',
      occurred_at: occurredAt,
      source: 'open_finance',
      external_id: externalId,
      description_raw: descriptionRaw,
      // Só no INSERT. Daqui para frente a descrição é do usuário, e a ingestão
      // nunca mais a toca.
      description: transaction.description?.trim() || descriptionRaw,
    });
  }

  if (toInsert.length > 0) {
    const { error } = await supabase.from('transactions').insert(toInsert);
    if (error) {
      // `23505` = alguém inseriu a mesma transação entre o nosso SELECT e o
      // INSERT (duas execuções do worker). É benigno: a linha existe.
      if (error.code !== '23505') {
        console.error('Falha ao inserir transações importadas', error);
      }
    }
  }

  return updated + toInsert.length;
}

/** Processa um evento. Lança para o chamador registrar a tentativa. */
async function processEvent(
  supabase: SupabaseClient,
  event: WebhookEventRow,
  apiKey: string,
): Promise<void> {
  const itemId = event.item_id;
  if (!itemId) {
    // Evento sem item (`connector/status_updated`, por exemplo): nada a
    // ingerir. Encerrado sem erro.
    return;
  }

  const { data: connection, error } = await supabase
    .from('open_finance_connections')
    .select('id, owner_id, item_id')
    .eq('item_id', itemId)
    .maybeSingle();

  if (error) throw new Error(`Falha ao ler a conexão: ${error.message}`);
  if (!connection) {
    // A conexão pode ter sido removida entre o webhook e agora.
    console.warn('Evento de item sem conexão correspondente, ignorado');
    return;
  }

  // **Sempre** o estado autoritativo, nunca o payload — regra do ADR 0005.
  const item = await pluggyGet<PluggyItem>(`/items/${itemId}`, apiKey);
  await syncConnection(supabase, connection as ConnectionRow, item);

  if (event.event_type === 'item/deleted') {
    const { error: deletedError } = await supabase
      .from('open_finance_connections')
      .update({ status: 'deleted' })
      .eq('id', connection.id);
    if (deletedError) console.error('Falha ao marcar conexão removida', deletedError);
    return;
  }

  if (event.event_type === 'transactions/deleted') {
    // Ver o item 4 do cabeçalho: não apagamos lançamento por conta própria.
    console.warn('transactions/deleted recebido; nada é apagado nesta versão');
    return;
  }

  const accounts = await syncAccounts(
    supabase,
    connection as ConnectionRow,
    apiKey,
  );
  if (accounts.size === 0) return;

  const spaceId = await personalSpaceId(supabase, connection.owner_id);
  if (spaceId == null) {
    throw new Error('Sem espaço pessoal para o dono da conexão');
  }

  let total = 0;
  for (const [externalAccountId, accountId] of accounts) {
    total += await syncTransactions(
      supabase,
      connection as ConnectionRow,
      apiKey,
      externalAccountId,
      accountId,
      spaceId,
    );
  }
  console.log('Ingestão concluída', {
    event: event.event_type,
    accounts: accounts.size,
    transactions: total,
  });
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Método não suportado.' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabase = createClient(
    requiredEnv('SUPABASE_URL'),
    requiredEnv('SUPABASE_SERVICE_ROLE_KEY'),
  );

  const { data: events, error } = await supabase
    .from('webhook_events')
    .select('id, event_id, event_type, item_id, attempts')
    .is('processed_at', null)
    .lt('attempts', MAX_ATTEMPTS)
    .order('received_at', { ascending: true })
    .limit(EVENT_BATCH);

  if (error) {
    console.error('Falha ao ler a fila de eventos', error);
    return new Response(JSON.stringify({ error: 'erro interno' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const pending = (events ?? []) as WebhookEventRow[];
  let processed = 0;
  let failed = 0;

  const apiKey = pending.length > 0 ? await getApiKey() : '';

  for (const event of pending) {
    try {
      await processEvent(supabase, event, apiKey);
      await supabase
        .from('webhook_events')
        .update({
          processed_at: new Date().toISOString(),
          attempts: event.attempts + 1,
          last_error: null,
        })
        .eq('id', event.id);
      processed += 1;
    } catch (error) {
      failed += 1;
      const attempts = event.attempts + 1;
      const message = error instanceof Error ? error.message : String(error);
      console.error('Falha ao processar evento', {
        event: event.event_type,
        attempts,
        message,
      });
      await supabase
        .from('webhook_events')
        .update({
          attempts,
          last_error: message.slice(0, 500),
          // Esgotadas as tentativas, encerra com o erro gravado em vez de
          // girar para sempre — o substituto do dead-letter do pgmq.
          ...(attempts >= MAX_ATTEMPTS
            ? { processed_at: new Date().toISOString() }
            : {}),
        })
        .eq('id', event.id);
    }
  }

  return new Response(
    JSON.stringify({ processed, failed, pending: pending.length }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
