// =========================================================================
// pluggy-connect-token — devolve ao cliente um Connect Token efêmero.
//
// Ver ADR 0005. Esta função existe por um motivo só: `CLIENT_ID` e
// `CLIENT_SECRET` da Pluggy **não podem** estar no binário do app, e a API Key
// que eles geram dá acesso total à conta. O único segredo que pode ir para o
// cliente é o Connect Token, que vale 30 minutos e só permite ler o item/contas
// recém-criados (a Pluggy devolve 403 se ele tentar mais que isso).
//
// Fluxo: cliente autenticado chama aqui → `POST /auth` (troca as credenciais
// pela apiKey) → `POST /connect_token` → devolve `accessToken`.
//
// ─────────────────────────────────────────────────────────────────────────
// TRÊS DECISÕES QUE VALEM REGISTRO
//
// 1. O `clientUserId` é `auth.uid()` extraído do **JWT verificado**, nunca do
//    corpo da requisição. Se o cliente pudesse informá-lo, um usuário
//    autenticado criaria um item no nome de outro — e como esse campo é a
//    rastreabilidade ponta a ponta do lado da Pluggy, o dado importado
//    apareceria amarrado à pessoa errada.
//
// 2. A troca de credenciais pela apiKey vive em `_shared/pluggy.ts`, junto do
//    cache por isolate — duas funções com lógicas de cache diferentes acabariam
//    estourando o rate limit de `/auth` por um caminho e não pelo outro.
//
// 3. Erro da Pluggy **não vaza para o cliente**. A resposta dela pode conter
//    detalhe de configuração da conta; o cliente recebe uma frase em português e
//    o diagnóstico fica no log da função. Mesma regra do `authErrorMessage` do
//    app: código de erro é contrato, texto de fornecedor não é.
// =========================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

import {
  ClientFacingError,
  getApiKey,
  requiredEnv,
} from '../_shared/pluggy.ts';

const PLUGGY_BASE_URL = 'https://api.pluggy.ai';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

/**
 * Cria o Connect Token. Com [itemId], o token serve para **atualizar** um item
 * existente — é o caminho de re-consentimento quando o consentimento expira ou
 * a credencial do banco muda. Sem ele, a Pluggy bloqueia a atualização via
 * widget por segurança.
 */
async function createConnectToken(
  apiKey: string,
  clientUserId: string,
  itemId: string | null,
): Promise<string> {
  const payload: Record<string, unknown> = {
    options: {
      clientUserId,
      webhookUrl: `${requiredEnv('SUPABASE_URL')}/functions/v1/pluggy-webhook`,
      // Evita criar item novo quando o usuário reconecta o mesmo banco com as
      // mesmas credenciais — sem isto, a mesma instituição viraria duas
      // conexões e as contas apareceriam duplicadas na aba Perfil.
      avoidDuplicates: true,
    },
  };
  if (itemId) {
    // `itemId` vai na raiz, não dentro de `options` (contrato da Pluggy).
    payload.itemId = itemId;
  }

  const response = await fetch(`${PLUGGY_BASE_URL}/connect_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-API-KEY': apiKey },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    console.error('Pluggy /connect_token falhou', {
      status: response.status,
      statusText: response.statusText,
      hasItemId: itemId !== null,
    });
    if (response.status === 404) {
      throw new ClientFacingError(
        404,
        'Essa conexão não foi encontrada no provedor. '
          + 'Conecte o banco novamente.',
      );
    }
    throw new ClientFacingError(
      502,
      'Não foi possível iniciar a conexão com o banco. '
        + 'Tente de novo em instantes.',
    );
  }

  const body = (await response.json()) as { accessToken?: string };
  if (!body.accessToken) {
    throw new ClientFacingError(
      502,
      'O provedor de Open Finance respondeu de forma inesperada.',
    );
  }
  return body.accessToken;
}

/**
 * Identifica o chamador pelo JWT do Supabase.
 *
 * `verify_jwt` já barra quem não tem token, mas isto vai além: precisamos do
 * `sub` para amarrar o item ao usuário, e `getUser` é o que confirma que o
 * token não foi revogado.
 */
async function resolveUserId(authorization: string | null): Promise<string> {
  if (!authorization) {
    throw new ClientFacingError(401, 'Sessão ausente. Entre de novo.');
  }

  const supabase = createClient(
    requiredEnv('SUPABASE_URL'),
    requiredEnv('SUPABASE_ANON_KEY'),
    { global: { headers: { Authorization: authorization } } },
  );

  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    throw new ClientFacingError(401, 'Sessão expirada. Entre de novo.');
  }
  return data.user.id;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Método não suportado.' }, 405);
  }

  try {
    const userId = await resolveUserId(request.headers.get('Authorization'));

    // Corpo é opcional: só o fluxo de re-consentimento manda `itemId`.
    let itemId: string | null = null;
    const rawBody = await request.text();
    if (rawBody.trim().length > 0) {
      const parsed = JSON.parse(rawBody) as { itemId?: unknown };
      if (typeof parsed.itemId === 'string' && parsed.itemId.length > 0) {
        itemId = parsed.itemId;
      }
    }

    const apiKey = await getApiKey();
    const accessToken = await createConnectToken(apiKey, userId, itemId);

    return jsonResponse({ accessToken }, 200);
  } catch (error) {
    if (error instanceof ClientFacingError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    if (error instanceof SyntaxError) {
      return jsonResponse({ error: 'Corpo da requisição inválido.' }, 400);
    }
    // Erro de configuração ou bug: o cliente não pode ver o texto, porque ele
    // nomeia variáveis de ambiente.
    console.error('pluggy-connect-token falhou', error);
    return jsonResponse(
      { error: 'Não foi possível iniciar a conexão. Tente de novo.' },
      500,
    );
  }
});
