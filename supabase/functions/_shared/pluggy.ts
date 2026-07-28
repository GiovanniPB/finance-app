// =========================================================================
// Cliente da API da Pluggy, compartilhado pelas Edge Functions.
//
// Existe para a troca de `CLIENT_ID`/`CLIENT_SECRET` pela apiKey viver num lugar
// só: duas funções chamando `POST /auth` com lógicas de cache diferentes é
// convite a estourar o rate limit dele por um caminho e não pelo outro.
// =========================================================================

const PLUGGY_BASE_URL = 'https://api.pluggy.ai';

// A apiKey da Pluggy vale 2h; renovamos 5 min antes para nunca usar uma que
// expire no meio da chamada seguinte.
const API_KEY_TTL_MS = 2 * 60 * 60 * 1000;
const API_KEY_RENEW_MARGIN_MS = 5 * 60 * 1000;

interface CachedApiKey {
  readonly apiKey: string;
  readonly fetchedAtMs: number;
}

let cachedApiKey: CachedApiKey | null = null;

/** Falha esperada, com frase pronta para a tela. */
export class ClientFacingError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    // Falha rápida, como o `AppEnv` faz no boot do app: uma função sem
    // credencial configurada deve dizer isso, não tentar e falhar com 401 da
    // Pluggy (que leria como credencial errada).
    throw new Error(`Variável de ambiente ausente: ${name}`);
  }
  return value;
}

/**
 * Troca `CLIENT_ID`/`CLIENT_SECRET` pela apiKey, reaproveitando a que estiver
 * em memória e ainda válida.
 *
 * O cache é **por isolate**, não no banco. A apiKey dá acesso total à conta da
 * Pluggy; persistir isso numa tabela para economizar uma chamada seria trocar
 * segurança por latência. Isolate reciclado apenas paga um `/auth` a mais.
 */
export async function getApiKey(): Promise<string> {
  const now = Date.now();
  if (
    cachedApiKey &&
    now - cachedApiKey.fetchedAtMs < API_KEY_TTL_MS - API_KEY_RENEW_MARGIN_MS
  ) {
    return cachedApiKey.apiKey;
  }

  const response = await fetch(`${PLUGGY_BASE_URL}/auth`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      clientId: requiredEnv('PLUGGY_CLIENT_ID'),
      clientSecret: requiredEnv('PLUGGY_CLIENT_SECRET'),
    }),
  });

  if (!response.ok) {
    // Nunca ecoar o corpo: em `401 CLIENT_KEYS_UNAUTHORIZED` ele confirmaria ao
    // chamador que as credenciais do servidor estão inválidas.
    console.error('Pluggy /auth falhou', {
      status: response.status,
      statusText: response.statusText,
    });
    throw new ClientFacingError(
      502,
      'Não foi possível falar com o provedor de Open Finance. '
        + 'Tente de novo em instantes.',
    );
  }

  const body = (await response.json()) as { apiKey?: string };
  if (!body.apiKey) {
    throw new ClientFacingError(
      502,
      'O provedor de Open Finance respondeu de forma inesperada.',
    );
  }

  cachedApiKey = { apiKey: body.apiKey, fetchedAtMs: now };
  return body.apiKey;
}

/**
 * `GET` autenticado na Pluggy.
 *
 * [path] pode ser caminho absoluto (`/items/x`) ou uma URL completa da própria
 * Pluggy — o cursor `next` de `/v2/transactions` volta como query relativa, e o
 * `createdTransactionsLink` do webhook volta como URL inteira.
 */
export async function pluggyGet<T>(
  path: string,
  apiKey: string,
): Promise<T> {
  const url = path.startsWith('http')
    ? path
    : `${PLUGGY_BASE_URL}${path.startsWith('/') ? path : `/${path}`}`;

  const response = await fetch(url, {
    headers: { 'X-API-KEY': apiKey },
  });

  if (!response.ok) {
    console.error('Pluggy GET falhou', {
      // Só o caminho, nunca a query: `createdTransactionsLink` e o cursor
      // carregam parâmetros que não precisam ir para o log.
      path: new URL(url).pathname,
      status: response.status,
    });
    throw new ClientFacingError(
      502,
      'O provedor de Open Finance não respondeu como esperado.',
    );
  }

  return (await response.json()) as T;
}

/** Item da Pluggy, nos campos que a ingestão usa (ver referência §7.1). */
export interface PluggyItem {
  id: string;
  status?: string;
  executionStatus?: string;
  error?: { code?: string; message?: string } | null;
  connector?: { id?: number; name?: string; imageUrl?: string };
  clientUserId?: string | null;
  lastUpdatedAt?: string | null;
  nextAutoSyncAt?: string | null;
  consentExpiresAt?: string | null;
}

/** Conta da Pluggy (ver referência §7.3). */
export interface PluggyAccount {
  id: string;
  type?: 'BANK' | 'CREDIT';
  subtype?: string;
  name?: string;
  marketingName?: string | null;
  balance?: number;
  currencyCode?: string;
  itemId?: string;
}

/** Transação da Pluggy (ver referência §7.4). */
export interface PluggyTransaction {
  id: string;
  description?: string;
  descriptionRaw?: string | null;
  currencyCode?: string;
  amount?: number;
  date?: string;
  type?: 'DEBIT' | 'CREDIT';
  status?: 'POSTED' | 'PENDING';
  providerId?: string | null;
  accountId?: string;
}

export interface CursorPage<T> {
  results?: T[];
  next?: string | null;
}
