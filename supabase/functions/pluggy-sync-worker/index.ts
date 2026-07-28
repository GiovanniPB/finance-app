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
// 3. PROPRIEDADE DE COLUNA: POR QUE NÃO SE USA `upsert` QUE ATUALIZA
//
// O `upsert` do supabase-js manda todas as colunas do payload no `DO UPDATE`.
// Isso apagaria `category_id` e a `description` que o usuário editou a cada
// sincronização — exatamente o que o ADR proíbe. Então a escrita é em duas
// etapas: descobre-se o que já existe por `external_id` e, para essas linhas, o
// UPDATE carrega **só** colunas da Pluggy. `description` é escrita **apenas no
// INSERT**; depois disso ela é do usuário.
//
// O INSERT usa `ignoreDuplicates: true`, que gera `ON CONFLICT DO NOTHING` —
// não é o `upsert` que a regra proíbe, porque ele **nunca atualiza coluna
// nenhuma**. Ele existe para uma colisão não derrubar a página inteira: um
// `INSERT` de várias linhas é atômico, e foi assim que três páginas de um cartão
// desapareceram em silêncio na primeira ingestão real (item 4).
//
// ─────────────────────────────────────────────────────────────────────────
// 4. FALHA DE ESCRITA SOBE, E FICA GRAVADA
//
// A primeira versão engolia erro de leitura (`return 0`) e tratava `23505` como
// benigno sem conferir quantas linhas entraram — então "página perdida" e
// "página gravada" eram indistinguíveis, e o evento era marcado como processado
// com sucesso nos dois casos. 1.433 lançamentos sumiram assim.
//
// Agora toda falha de escrita **lança**: o `attempts` sobe, a mensagem vai para
// `last_error` (legível por SQL, diferente de `console.log`) e o evento volta na
// próxima passada. E o resultado de cada página — quantas chegaram, quantas
// foram filtradas, quantas colidiram, quantas entraram — é gravado no `payload`
// do evento, ao lado da convenção observada.
//
// ─────────────────────────────────────────────────────────────────────────
// 5. O QUE ESTA FATIA NÃO FAZ
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
  PluggyNotFound,
  type PluggyTransaction,
  pluggyGet,
  requiredEnv,
} from '../_shared/pluggy.ts';

import {
  dedupeByExternalId,
  type Direction,
  directionByType,
  resolveDirection,
} from '../_shared/ingest.ts';

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
/// mora em `type` na nossa tabela, como em todo o resto do app. Quem decide essa
/// direção a partir do dado da Pluggy é `resolveDirection`, em
/// `_shared/ingest.ts` — e é lá que está a tabela-verdade medida nos dois
/// conectores, com teste.
function toMinor(amount: number | undefined): number | null {
  if (typeof amount !== 'number' || !Number.isFinite(amount)) return null;
  const minor = Math.round(Math.abs(amount) * 100);
  return minor > 0 ? minor : null;
}

/**
 * Aplica a regra de direção (`_shared/ingest.ts`) e conta a discordância com o
 * `type` declarado.
 *
 * A tabela-verdade, o porquê de o tipo de conta decidir e o caso conhecido do
 * sandbox moram no módulo puro, junto do teste que os exercita. Aqui fica só a
 * parte que precisa de estado: quantas linhas da página discordaram.
 */
function directionOf(
  transaction: PluggyTransaction,
  accountType: string,
  disagreements: { count: number },
): Direction {
  const bySign = resolveDirection(transaction.amount, accountType);
  const byType = directionByType(transaction.type, accountType);

  if (byType !== null && byType !== bySign) {
    // Com a regra ciente do tipo de conta, os dois eixos concordaram em **tudo**
    // que chegou de conta real. Discordância aqui é anomalia de verdade — uma
    // convenção nova do fornecedor —, não o barulho esperado que era antes. A
    // contagem vai para o `payload` do evento; `console.warn` não é legível por
    // SQL nem pelo CLI desta versão.
    disagreements.count += 1;
  }

  return bySign;
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
    throw new Error(`Falha ao resolver o espaço pessoal: ${error.message}`);
  }
  return data?.id ?? null;
}

/**
 * Marca a conexão como removida na Pluggy.
 *
 * Um caminho só para os dois jeitos de descobrir isso — o evento
 * `item/deleted` e o 404 no `GET /items` —, porque o efeito precisa ser
 * idêntico: o app tem de parar de mostrar a conexão como conectada.
 */
async function markConnectionDeleted(
  supabase: SupabaseClient,
  connectionId: string,
): Promise<void> {
  const { error } = await supabase
    .from('open_finance_connections')
    .update({ status: 'deleted', provider_execution_status: null })
    .eq('id', connectionId);
  if (error) console.error('Falha ao marcar conexão removida', error);
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
 * Registra a convenção de direção que a Pluggy usou, cruzada com o tipo de
 * conta. **Instrumentação permanente, não sonda temporária.**
 *
 * Por que existe: em 2026-07-28 a primeira ingestão real gravou 27 compras de
 * cartão (Netflix, Spotify, academia) como **receita**. A soma delas batia
 * exatamente com a fatura, então eram gasto sem dúvida. E a doc oficial da
 * Pluggy afirma o contrário do que chegou — ela diz que compra em cartão vem
 * como `DEBIT` com valor positivo; o que chegou não era `DEBIT`.
 *
 * A convenção de um agregador **depende do tipo de conta** (numa conta corrente
 * o dinheiro sai; num cartão a compra aumenta a dívida) e pode divergir entre
 * sandbox e produção. Sem este log, a próxima divergência volta a ser descoberta
 * por alguém conferindo extrato à mão.
 *
 * O sinal é registrado porque `toMinor` o descarta com `Math.abs` — depois de
 * gravado, a informação não existe mais em lugar nenhum.
 */
function observeDirectionConvention(
  account: IngestedAccount,
  transactions: PluggyTransaction[],
): Record<string, unknown> {
  const tally = { DEBIT: 0, CREDIT: 0, ausente: 0 };
  const sign = { positivo: 0, negativo: 0, zero: 0 };
  const amostra: string[] = [];

  for (const transaction of transactions) {
    if (transaction.type === 'DEBIT') tally.DEBIT += 1;
    else if (transaction.type === 'CREDIT') tally.CREDIT += 1;
    else tally.ausente += 1;

    const amount = transaction.amount;
    if (typeof amount !== 'number') continue;
    if (amount > 0) sign.positivo += 1;
    else if (amount < 0) sign.negativo += 1;
    else sign.zero += 1;

    // Três exemplos bastam para ler a convenção; descrição é do extrato do
    // usuário, então só o começo dela entra.
    if (amostra.length < 3) {
      amostra.push(
        `${transaction.type ?? 'sem-type'} ${amount} `
          + `"${(transaction.description ?? '').slice(0, 24)}"`,
      );
    }
  }

  return { accountType: account.accountType, porType: tally, porSinal: sign, amostra };
}

/**
 * Persiste a observação da convenção junto do evento que a produziu.
 *
 * Por que no banco e não só em `console.log`: a saída de console das Edge
 * Functions **não** é legível por SQL nem pelo CLI (`supabase functions logs`
 * não existe nesta versão) — só pelo dashboard. Em 2026-07-28 isso travou o
 * diagnóstico do bug de direção do cartão: a instrumentação existia, tinha
 * rodado, e não havia como ler o resultado sem alguém abrir o navegador.
 *
 * Fica no `payload` do próprio evento porque é observação **sobre aquela
 * ingestão**: some junto quando `webhook_events` for podado, e não inventa
 * tabela para um dado que só serve acompanhado do evento. A chave começa com
 * `_` para não colidir com campo que a Pluggy mande.
 */
async function recordConvention(
  supabase: SupabaseClient,
  eventRowId: string,
  observation: unknown,
): Promise<void> {
  const { data, error: readError } = await supabase
    .from('webhook_events')
    .select('payload')
    .eq('id', eventRowId)
    .maybeSingle();
  if (readError || !data) return;

  const payload = (data.payload ?? {}) as Record<string, unknown>;
  const existing = Array.isArray(payload._convencao) ? payload._convencao : [];

  const { error } = await supabase
    .from('webhook_events')
    .update({ payload: { ...payload, _convencao: [...existing, observation] } })
    .eq('id', eventRowId);
  if (error) console.error('Falha ao registrar a convenção observada', error);
}

/** Nossa conta, do ponto de vista da ingestão de transação. */
interface IngestedAccount {
  readonly id: string;
  /// Precisa acompanhar porque a convenção de direção da Pluggy **depende** do
  /// tipo de conta: numa conta corrente o dinheiro sai; num cartão a compra
  /// aumenta a dívida. Ver `logDirectionConvention`.
  readonly accountType: string;
}

/**
 * Traz as contas do item. Devolve o mapa `id da Pluggy → nossa conta`, que a
 * sincronização de transação usa.
 */
async function syncAccounts(
  supabase: SupabaseClient,
  connection: ConnectionRow,
  apiKey: string,
): Promise<Map<string, IngestedAccount>> {
  const byExternalId = new Map<string, IngestedAccount>();

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

  // Lança pelo mesmo motivo da leitura de transações (item 4): devolver o mapa
  // vazio aqui encerraria o evento com sucesso e sem ingerir nada.
  if (readError) {
    throw new Error(`Falha ao ler as contas existentes: ${readError.message}`);
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
      if (error) {
        throw new Error(
          `Falha ao atualizar conta importada: ${error.message}`,
        );
      }
      byExternalId.set(account.id, {
        id: known,
        accountType: mapAccountType(account),
      });
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
      throw new Error(`Falha ao inserir conta importada: ${error.message}`);
    }
    if (inserted?.id) {
      byExternalId.set(account.id, {
        id: inserted.id as string,
        accountType: mapAccountType(account),
      });
    }
  }

  return byExternalId;
}

/** Traz as transações de uma conta, paginando pelo cursor. */
async function syncTransactions(
  supabase: SupabaseClient,
  connection: ConnectionRow,
  apiKey: string,
  externalAccountId: string,
  account: IngestedAccount,
  spaceId: string,
  eventRowId: string,
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
      const observation = {
        ...observeDirectionConvention(account, transactions),
        pagina: pages,
      };

      // A observação é gravada **junto** com o resultado da escrita, e também
      // quando a escrita falha: uma página que não entrou tem de deixar rastro
      // legível por SQL, que é justamente o que faltava quando três delas
      // desapareceram.
      try {
        const outcome = await writeTransactions(
          supabase,
          transactions,
          connection,
          account,
          spaceId,
        );
        await recordConvention(supabase, eventRowId, {
          ...observation,
          escrita: outcome,
        });
        written += outcome.inseridas + outcome.atualizadas;
      } catch (error) {
        await recordConvention(supabase, eventRowId, {
          ...observation,
          escrita: {
            erro: error instanceof Error ? error.message : String(error),
          },
        });
        throw error;
      }
    }

    // O cursor volta como query relativa (`?accountId=...&after=...`); o
    // `pluggyGet` aceita caminho ou URL, mas a query solta precisa do caminho.
    const next = page.next;
    path = next ? (next.startsWith('?') ? `/v2/transactions${next}` : next)
      : null;
  }

  if (path) {
    console.warn('Limite de páginas atingido; o resto vem na próxima passada', {
      accountId: account.id,
      pages,
    });
  }

  return written;
}

/// O que uma página de transação produziu. Gravado no `payload` do evento: é a
/// única forma de saber, por SQL, se uma página entrou ou se sumiu.
interface WriteOutcome {
  /// Chegaram na página (já sem as `PENDING`).
  readonly recebidas: number;
  /// Recusadas por não ter valor utilizável ou data válida.
  readonly semValorOuData: number;
  /// Descartadas por repetir um `external_id` da **mesma** página.
  readonly colididas: number;
  readonly existentes: number;
  readonly atualizadas: number;
  readonly inseridas: number;
  /// Linhas que o INSERT não gravou por já existirem (corrida entre execuções).
  readonly ignoradas: number;
  /// Linhas cujo sinal discordou do `type` declarado.
  readonly direcaoEmDuvida: number;
}

/**
 * Grava um lote de transações respeitando a propriedade de coluna.
 *
 * Ver o item 3 do cabeçalho: o UPDATE das linhas conhecidas carrega só colunas
 * da Pluggy; `description` e `category_id` nunca aparecem nele. E o item 4:
 * falha de escrita **lança** em vez de virar um número que parece sucesso.
 */
async function writeTransactions(
  supabase: SupabaseClient,
  transactions: PluggyTransaction[],
  connection: ConnectionRow,
  account: IngestedAccount,
  spaceId: string,
): Promise<WriteOutcome> {
  const disagreements = { count: 0 };

  // `providerId` é preferido quando existe (conexão regulada): ele é o mesmo
  // para a mesma transação em items diferentes, então sobrevive a reconectar o
  // banco. Ver o item 4 do cabeçalho da migration 20260728033219.
  const usable = transactions
    .map((transaction) => ({
      externalId: transaction.providerId?.trim() || transaction.id,
      value: {
        transaction,
        amountMinor: toMinor(transaction.amount),
        occurredAt: isoOrNull(transaction.date),
      },
    }))
    .filter((entry) =>
      entry.value.amountMinor !== null && entry.value.occurredAt !== null
    );

  const { unique: keyed, collided } = dedupeByExternalId(usable);

  const empty: WriteOutcome = {
    recebidas: transactions.length,
    semValorOuData: transactions.length - usable.length,
    colididas: collided,
    existentes: 0,
    atualizadas: 0,
    inseridas: 0,
    ignoradas: 0,
    direcaoEmDuvida: 0,
  };
  if (keyed.length === 0) return empty;

  const { data: existing, error: readError } = await supabase
    .from('transactions')
    .select('id, external_id')
    .eq('account_id', account.id)
    .in('external_id', keyed.map((entry) => entry.externalId));

  // Lança: uma leitura que falhou não distingue "nada existe" de "não sei o que
  // existe", e a primeira versão tratava as duas como a primeira.
  if (readError) {
    throw new Error(
      `Falha ao ler transações existentes: ${readError.message}`,
    );
  }
  const existingByExternal = new Map<string, string>(
    (existing ?? [])
      .filter((row) => typeof row.external_id === 'string')
      .map((row) => [row.external_id as string, row.id as string]),
  );

  const toInsert: Record<string, unknown>[] = [];
  let updated = 0;

  for (const { externalId, value } of keyed) {
    const { transaction, amountMinor, occurredAt } = value;
    const known = existingByExternal.get(externalId);
    const descriptionRaw = transaction.descriptionRaw?.trim()
      || transaction.description?.trim() || null;
    const type = directionOf(transaction, account.accountType, disagreements);

    if (known) {
      const { error } = await supabase
        .from('transactions')
        .update({
          amount_minor: amountMinor,
          currency: transaction.currencyCode ?? 'BRL',
          occurred_at: occurredAt,
          type,
          description_raw: descriptionRaw,
        })
        .eq('id', known);
      // Este UPDATE é também o reparo: uma direção gravada errado numa versão
      // anterior é corrigida no reprocessamento.
      if (error) {
        throw new Error(
          `Falha ao atualizar transação importada: ${error.message}`,
        );
      }
      updated += 1;
      continue;
    }

    toInsert.push({
      space_id: spaceId,
      account_id: account.id,
      created_by: connection.owner_id,
      type,
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

  let inserted = 0;
  if (toInsert.length > 0) {
    // `ignoreDuplicates: true` gera `ON CONFLICT DO NOTHING`: não atualiza
    // coluna nenhuma (a regra do item 3 continua valendo) e uma linha que
    // apareceu entre o SELECT e o INSERT deixa de derrubar a página inteira.
    // O `select` devolve **só o que entrou**, que é como a contagem passa a ser
    // verdade em vez de `toInsert.length`.
    const { data, error } = await supabase
      .from('transactions')
      .upsert(toInsert, {
        onConflict: 'account_id,external_id',
        ignoreDuplicates: true,
      })
      .select('id');

    if (error) {
      throw new Error(
        `Falha ao inserir transações importadas: ${error.message}`,
      );
    }
    inserted = data?.length ?? 0;
  }

  return {
    ...empty,
    existentes: existingByExternal.size,
    atualizadas: updated,
    inseridas: inserted,
    ignoradas: toInsert.length - inserted,
    direcaoEmDuvida: disagreements.count,
  };
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

  // `item/deleted` é tratado **antes** de qualquer busca, e a ordem é o ponto.
  // A regra do ADR 0005 ("sempre `GET /items/{id}` primeiro, nunca confie no
  // payload") não vale para deleção: o item já não existe, então o GET responde
  // 404 por definição. A primeira versão buscava primeiro e o 404 subia como
  // erro — o ramo abaixo nunca executava, o evento gastava as cinco tentativas e
  // a conexão ficava `active` no app apontando para um item que morreu.
  // Visto em produção em 2026-07-28, com três conexões nesse estado.
  if (event.event_type === 'item/deleted') {
    await markConnectionDeleted(supabase, connection.id);
    return;
  }

  // **Sempre** o estado autoritativo, nunca o payload — regra do ADR 0005.
  let item: PluggyItem;
  try {
    item = await pluggyGet<PluggyItem>(`/items/${itemId}`, apiKey);
  } catch (error) {
    // O item pode ter sido removido entre o webhook e agora — inclusive por
    // limpeza automática de sandbox. Isso encerra o evento em vez de gastar as
    // cinco tentativas contra um 404 que nunca vai mudar.
    if (error instanceof PluggyNotFound) {
      console.warn('Item já não existe na Pluggy; conexão marcada como removida');
      await markConnectionDeleted(supabase, connection.id);
      return;
    }
    throw error;
  }
  await syncConnection(supabase, connection as ConnectionRow, item);

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
  for (const [externalAccountId, account] of accounts) {
    total += await syncTransactions(
      supabase,
      connection as ConnectionRow,
      apiKey,
      externalAccountId,
      account,
      spaceId,
      event.id,
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
