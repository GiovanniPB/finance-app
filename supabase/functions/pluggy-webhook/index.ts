// =========================================================================
// pluggy-webhook — recebe as notificações da Pluggy e as enfileira.
//
// Ver ADR 0005 e a revisão de 2026-07-28 dele. Esta função faz **três** coisas e
// nada mais: valida o mínimo, grava em `webhook_events`, responde 2xx. O
// processamento é do `pluggy-sync-worker`.
//
// ─────────────────────────────────────────────────────────────────────────
// POR QUE ELA NÃO EXIGE HEADER SECRETO — E O ADR PEDIA
//
// O ADR mandava "validar header secreto + IP allowlist". Ao implementar,
// descobriu-se que **não existe header secreto neste caminho**: a referência da
// Pluggy (§8.5) diz que `headers` customizados só podem ser configurados ao
// criar uma **instância de webhook** por `POST /webhooks`. O nosso `webhookUrl`
// vai no Connect Token, e por esse caminho a Pluggy manda o POST **sem header
// nenhum**. Exigir o header recusaria 100% dos webhooks — falha total e
// silenciosa, exatamente o modo de falha que a revisão do ADR queria evitar.
//
// A autoridade, então, não vem de quem chama. Vem de três coisas:
//
//  1. **O payload nunca é confiado.** Ele serve para saber *que algo mudou*, em
//     qual item. Todo dado vem depois, do `GET /items/{id}` autenticado com a
//     nossa apiKey — como o próprio ADR já mandava.
//  2. **Só item que é nosso é aceito.** Se o `itemId` não existe em
//     `open_finance_connections`, o evento é descartado. Um estranho não
//     consegue nos fazer buscar nada que já não seja nosso, nem injetar linha.
//  3. **`event_id` é `unique`.** Reenvio da Pluggy (até 9 tentativas) e
//     repetição de terceiro colidem e são descartados pelo banco.
//
// O que sobra de exposição é ruído: alguém pode disparar re-buscas de itens que
// já são nossos. Custa chamada à Pluggy, não vaza dado e não escreve nada que a
// Pluggy não confirme. Quando houver uma instância de webhook registrada por
// `POST /webhooks` com header, ele **é** validado (ver `expectedSecret`) — o
// código aceita os dois mundos.
//
// A IP allowlist entra como **aviso**, não recusa: IP de fornecedor muda sem
// aviso, e recusar por isso pararia a sincronização sem erro visível.
//
// ─────────────────────────────────────────────────────────────────────────
// POR QUE RESPONDER ANTES DE PROCESSAR
//
// A Pluggy exige 2xx em menos de 5 segundos (§8.5) e re-tenta o que demora. Um
// `GET /items` + `/accounts` + páginas de `/v2/transactions` não caberia nisso.
// Então aqui só se grava a linha, e o worker é acionado **sem `await`** — se ele
// falhar ou demorar, o evento continua em `webhook_events` com
// `processed_at is null`, e a próxima passada o pega.
// =========================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

import { requiredEnv } from '../_shared/pluggy.ts';

/// IP de origem documentado da Pluggy. Usado só para log (ver cabeçalho).
const PLUGGY_SOURCE_IP = '52.67.145.81';

interface WebhookPayload {
  event?: string;
  eventId?: string;
  itemId?: string;
  clientUserId?: string | null;
  [key: string]: unknown;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Método não suportado.' }, 405);
  }

  // Quando existir uma instância de webhook registrada com header secreto, ele
  // passa a ser exigido. Sem a variável configurada, não há o que exigir.
  const expectedSecret = Deno.env.get('PLUGGY_WEBHOOK_SECRET');
  if (expectedSecret) {
    const received = request.headers.get('authorization');
    if (received !== expectedSecret) {
      console.warn('Webhook recusado: header secreto ausente ou incorreto');
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
  }

  const sourceIp = request.headers.get('x-forwarded-for')?.split(',')[0]
    ?.trim();
  if (sourceIp && sourceIp !== PLUGGY_SOURCE_IP) {
    // Aviso, não recusa: se a Pluggy mudar de IP, a sincronização não pode
    // parar em silêncio. Ver a revisão do ADR 0005.
    console.warn('Webhook de IP não esperado', { sourceIp });
  }

  let payload: WebhookPayload;
  try {
    payload = (await request.json()) as WebhookPayload;
  } catch (_error) {
    // 400 e não 5xx: corpo inválido não melhora com retry.
    return jsonResponse({ error: 'Corpo inválido.' }, 400);
  }

  const eventId = payload.eventId;
  const event = payload.event;
  if (!eventId || !event) {
    console.warn('Webhook sem eventId ou event', { event, hasId: !!eventId });
    return jsonResponse({ error: 'Payload incompleto.' }, 400);
  }

  const supabase = createClient(
    requiredEnv('SUPABASE_URL'),
    // Service role: esta função escreve em `webhook_events`, que tem RLS ligada
    // e **nenhuma policy** — é o jeito de dizer "server-only".
    requiredEnv('SUPABASE_SERVICE_ROLE_KEY'),
  );

  const itemId = typeof payload.itemId === 'string' ? payload.itemId : null;

  // Item que não é nosso não vira trabalho. Responde 2xx de propósito: 4xx faria
  // a Pluggy re-tentar nove vezes um evento que nunca vamos querer.
  if (itemId) {
    const { data: connection, error } = await supabase
      .from('open_finance_connections')
      .select('id')
      .eq('item_id', itemId)
      .maybeSingle();

    if (error) {
      console.error('Falha ao verificar a conexão do webhook', error);
      // 500 aqui é correto: foi falha nossa e o retry da Pluggy ajuda.
      return jsonResponse({ error: 'erro interno' }, 500);
    }
    if (!connection) {
      console.warn('Webhook de item desconhecido, descartado', { event });
      return jsonResponse({ received: true, ignored: true }, 200);
    }
  }

  const { error: insertError } = await supabase.from('webhook_events').insert({
    event_id: eventId,
    event_type: event,
    item_id: itemId,
    payload,
  });

  if (insertError) {
    // `23505` é unique_violation: o mesmo `eventId` já está registrado. É o
    // caminho **esperado** num reenvio, e 2xx é a resposta certa — repetir o
    // processamento é justamente o que a unique existe para impedir.
    if (insertError.code === '23505') {
      return jsonResponse({ received: true, duplicate: true }, 200);
    }
    console.error('Falha ao gravar o evento de webhook', insertError);
    return jsonResponse({ error: 'erro interno' }, 500);
  }

  // Aciona o worker **sem esperar**: o prazo de 5s da Pluggy não cabe uma
  // ingestão. Se isto falhar, o evento fica pendente e a próxima passada o pega
  // — por isso o `catch` só registra.
  const workerUrl = `${requiredEnv('SUPABASE_URL')}/functions/v1/pluggy-sync-worker`;
  fetch(workerUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${requiredEnv('SUPABASE_SERVICE_ROLE_KEY')}`,
    },
    body: JSON.stringify({ triggeredByEventId: eventId }),
  }).catch((error) => {
    console.error('Não foi possível acionar o worker', error);
  });

  return jsonResponse({ received: true }, 200);
});
