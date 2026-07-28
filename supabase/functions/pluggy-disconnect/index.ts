// =========================================================================
// pluggy-disconnect — cancela o acesso ao banco no provedor.
//
// Ver ADR 0005. Existe porque `DELETE /items/{id}` exige a **API Key** da conta
// Pluggy, que dá acesso total e não pode sair do servidor. Sem esta função,
// "Remover banco" apagaria a linha do nosso banco e deixaria o item vivo lá: o
// consentimento no banco do usuário continuaria valendo, a Pluggy continuaria
// sincronizando e cobrando, e a tela teria dito que o acesso foi cancelado. Uma
// promessa falsa sobre acesso a dado bancário é pior que a ausência do botão.
//
// ─────────────────────────────────────────────────────────────────────────
// 1. QUEM AUTORIZA É A RLS, NÃO ESTA FUNÇÃO
//
// A conexão é lida com um cliente que carrega o **Authorization do chamador**,
// então a policy `open_finance_connections_select_own` é quem decide se aquele
// item é dele. Uma verificação escrita aqui (`owner_id === userId`) seria uma
// segunda cópia da mesma regra, e cópias divergem — a de RLS já vale para o app
// inteiro. Consequência prática: item de outro usuário responde **404**, não
// 403, porque para quem chama ele não existe.
//
// 2. ESTA FUNÇÃO NÃO APAGA A LINHA
//
// Quem apaga é o cliente, pelo caminho normal do PowerSync — offline-first, com
// a escrita na fila. Manter um único escritor da linha evita a corrida entre a
// função e o upload do cliente, e o caso de a revogação passar e a linha
// sobreviver **se autocura**: a próxima passada do worker leva 404 no
// `GET /items/{id}`, e o `PluggyNotFound` já marca a conexão como removida.
//
// 3. 404 DA PLUGGY É SUCESSO
//
// Item que já não existe é o estado desejado. Tratá-lo como erro faria a segunda
// tentativa de remover falhar para sempre, prendendo no app uma conexão que já
// morreu lá.
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
 * Descobre o `item_id` da conexão, **pela ótica de quem chamou**.
 *
 * O `Authorization` do chamador vai no cliente de propósito: ver o item 1 do
 * cabeçalho. Conexão que a RLS esconde é indistinguível de conexão inexistente,
 * e é assim que deve ser.
 */
async function resolveItemId(
  authorization: string,
  connectionId: string,
): Promise<string> {
  const supabase = createClient(
    requiredEnv('SUPABASE_URL'),
    requiredEnv('SUPABASE_ANON_KEY'),
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: user, error: userError } = await supabase.auth.getUser();
  if (userError || !user.user) {
    throw new ClientFacingError(401, 'Sessão expirada. Entre de novo.');
  }

  const { data, error } = await supabase
    .from('open_finance_connections')
    .select('item_id')
    .eq('id', connectionId)
    .maybeSingle();

  if (error) {
    console.error('Falha ao ler a conexão', { code: error.code });
    throw new ClientFacingError(
      502,
      'Não foi possível ler essa conexão agora. Tente de novo em instantes.',
    );
  }
  if (!data?.item_id) {
    throw new ClientFacingError(404, 'Essa conexão não existe mais.');
  }
  return data.item_id as string;
}

/// Revoga o item na Pluggy. 404 é sucesso — ver o item 3 do cabeçalho.
async function deleteItem(apiKey: string, itemId: string): Promise<void> {
  const response = await fetch(
    `${PLUGGY_BASE_URL}/items/${encodeURIComponent(itemId)}`,
    { method: 'DELETE', headers: { 'X-API-KEY': apiKey } },
  );

  if (response.ok || response.status === 404) return;

  // Nunca ecoar o corpo: ele pode descrever a configuração da conta Pluggy.
  console.error('Pluggy DELETE /items falhou', {
    status: response.status,
    statusText: response.statusText,
  });
  throw new ClientFacingError(
    502,
    'Não foi possível cancelar o acesso no provedor. '
      + 'Tente de novo em instantes.',
  );
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Método não suportado.' }, 405);
  }

  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) {
      throw new ClientFacingError(401, 'Sessão ausente. Entre de novo.');
    }

    let connectionId: string | null = null;
    const rawBody = await request.text();
    if (rawBody.trim().length > 0) {
      const parsed = JSON.parse(rawBody) as { connectionId?: unknown };
      if (
        typeof parsed.connectionId === 'string'
        && parsed.connectionId.length > 0
      ) {
        connectionId = parsed.connectionId;
      }
    }
    if (connectionId == null) {
      throw new ClientFacingError(400, 'Conexão não informada.');
    }

    const itemId = await resolveItemId(authorization, connectionId);
    await deleteItem(await getApiKey(), itemId);

    return jsonResponse({ revoked: true }, 200);
  } catch (error) {
    if (error instanceof ClientFacingError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error('Falha inesperada em pluggy-disconnect', error);
    return jsonResponse({ error: 'Erro interno.' }, 500);
  }
});
