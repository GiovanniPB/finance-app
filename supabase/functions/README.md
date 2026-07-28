# Edge Functions — pipeline de Open Finance

Implementa o ADR 0005: **todo dado de Open Finance entra pelo servidor**. O
cliente nunca fala com a Pluggy a não ser pelo widget Connect, e mesmo aí só com
um token efêmero que uma função daqui emitiu.

```
Pluggy → pluggy-webhook → webhook_events → pluggy-sync-worker → Postgres
                                                      ↓
                                        PowerSync (WAL) → SQLite local
```

## Estado

| Função | `verify_jwt` | Estado |
|---|---|---|
| `pluggy-connect-token` | `true` | ✅ Deployada e **exercitada de verdade** — o widget carregou e o fluxo completou no simulador. |
| `pluggy-webhook` | **`false`** | ✅ Deployada. 6 eventos reais recebidos e enfileirados; guardas verificadas (405 em GET, 400 em corpo inválido, 200 sem escrita em item de terceiro). |
| `pluggy-sync-worker` | `true` | ✅ Deployada e rodou contra sandbox **e** conta real. Duas correções saíram dessa passagem: direção em cartão e perda silenciosa de página. |
| `pluggy-disconnect` | `true` | Escrita. Cancela o acesso no banco (`DELETE /items/{id}`). **Não deployada, nunca rodou.** |

`_shared/pluggy.ts` concentra a troca de `CLIENT_ID`/`CLIENT_SECRET` pela apiKey
(com cache por isolate) e o `GET` autenticado — duas funções com caches
independentes acabariam estourando o rate limit de `/auth` por um caminho e não
pelo outro.

`_shared/ingest.ts` guarda as **decisões puras** da ingestão: direção do
lançamento e dedup de lote. Ficam separadas porque é o código que erra em
silêncio — não estoura, vira dinheiro errado no extrato de alguém — e porque
assim dá para testá-las sem Deno, sem rede e sem device.

## Testes

```bash
node --test 'supabase/functions/_shared/*.test.ts'
```

Não precisa de Deno nem de Docker: `_shared/ingest.ts` não importa nada, e o Node
24 executa TypeScript direto. O que o arquivo de teste guarda é a **tabela-verdade
medida** nos dois conectores, copiada da instrumentação gravada em
`webhook_events.payload._convencao` — não a documentação, que já divergiu do que
chegou.

## Por que "Remover banco" precisa de servidor

`DELETE /items/{id}` exige a **API Key**, que dá acesso total à conta Pluggy e
não pode sair do servidor. Sem `pluggy-disconnect`, o botão apagaria a linha do
nosso banco e deixaria o item vivo lá: o consentimento no banco do usuário
continuaria valendo, a Pluggy continuaria sincronizando, e a tela teria dito que
o acesso foi cancelado. Promessa falsa sobre acesso a dado bancário é pior que a
ausência do botão.

Três decisões dela:

1. **Quem autoriza é a RLS.** A conexão é lida com um cliente que carrega o
   `Authorization` do chamador, então a policy `..._select_own` decide se aquele
   item é dele. Uma checagem `owner_id === userId` escrita na função seria uma
   segunda cópia da mesma regra. Consequência: item de outro usuário responde
   **404**, não 403 — para quem chama, ele não existe.
2. **A função não apaga a linha.** Quem apaga é o cliente, pelo caminho normal do
   PowerSync. Um escritor só evita corrida com o upload, e o caso "revogou mas a
   linha ficou" **se autocura**: a próxima passada do worker leva 404 no
   `GET /items/{id}` e o `PluggyNotFound` marca a conexão como removida.
3. **404 da Pluggy é sucesso.** Item que já não existe é o estado desejado;
   tratá-lo como erro prenderia no app uma conexão que já morreu lá.

## Por que o webhook não tem `verify_jwt` nem header secreto

Quem chama é a Pluggy, que não tem sessão do Supabase — daí `verify_jwt = false`.
E **não há header secreto possível neste caminho**: a Pluggy só envia `headers`
customizados em webhook registrado por `POST /webhooks` (referência §8.5), e o
nosso `webhookUrl` vai no Connect Token. Exigir o header recusaria 100% dos
webhooks.

A autoridade vem de três outros lugares:

1. **O payload nunca é confiado** — todo dado vem do `GET /items/{id}`
   autenticado com a nossa apiKey.
2. **Só item que já existe em `open_finance_connections` é aceito.**
3. **`event_id` é `unique`** — reenvio da Pluggy (até 9 tentativas) colide.

Um terceiro consegue, no máximo, disparar re-buscas de itens que já são nossos:
custa chamada à Pluggy, não vaza dado e não escreve nada que a Pluggy não
confirme. Se um dia houver instância registrada com header, `PLUGGY_WEBHOOK_SECRET`
liga a exigência e ele **é** validado.

## Segredos

| Variável | Origem | Obrigatória |
|---|---|---|
| `PLUGGY_CLIENT_ID` | Dashboard da Pluggy → Application | sim |
| `PLUGGY_CLIENT_SECRET` | idem | sim |
| `PLUGGY_WEBHOOK_SECRET` | escolha sua, se registrar webhook por `POST /webhooks` | não |
| `SUPABASE_URL` · `SUPABASE_ANON_KEY` · `SUPABASE_SERVICE_ROLE_KEY` | injetadas pelo runtime | — |

```bash
supabase secrets set PLUGGY_CLIENT_ID=... PLUGGY_CLIENT_SECRET=...
```

**Sandbox vs. produção.** A aplicação **Demo** do dashboard só conecta
conectores de sandbox (credenciais de teste: `user-ok` / `password-ok`, MFA
`123456`). Conta real exige credenciais de uma aplicação de **produção** — o
[Meu Pluggy](https://www.pluggy.ai/meu-pluggy) dá isso de graça, sem prazo, para
contas nominais do próprio titular. Trocar as credenciais troca também de
aplicação: os items criados pela anterior deixam de ser visíveis.

## Deploy

```bash
supabase functions deploy pluggy-connect-token pluggy-webhook \
  pluggy-sync-worker pluggy-disconnect
```

## Limitações conhecidas

- **O typecheck local não exige instalar Deno**, mas exige rede:
  `cd supabase/functions && npx -y deno@2.1.4 check pluggy-*/index.ts` baixa o
  Deno na hora e resolve os imports `jsr:`. `deno lint` no mesmo caminho. É mais
  rápido que descobrir erro de tipo no `deploy`.
- **A convenção de direção é conhecida em dois conectores, não em N.** Sandbox e
  Nubank; o cartão do sandbox inverte os dois campos e nenhuma regra o acerta.
  A discordância entre sinal e `type` é contada por página no `payload` do
  evento, que é onde a terceira convenção vai aparecer.
- **`transactions/deleted` não apaga nada.** Apagar lançamento que o usuário já
  categorizou (ou ligou a uma meta) é decisão de produto.
- **`PENDING` é ignorada.** Não há coluna para marcá-la, e exibi-la como
  liquidada faria o saldo mentir.
- **Sem `pg_cron`.** O worker é acionado pelo webhook, sem `await`. Se essa
  chamada falhar, o evento fica em `webhook_events` com `processed_at is null` e
  **ninguém o pega** até o próximo webhook. Uma varredura periódica é o próximo
  passo natural.
- **Investimentos, identidade e pagamentos** ficam fora.

## Diagnóstico

Logs das funções: `get_logs` do MCP do Supabase (serviço `edge-function`), ou o
dashboard. Foi assim que se descobriu que a Pluggy estava batendo em
`/pluggy-webhook` e levando 404 antes de a função existir.

Fila pendente:

```sql
select event_type, attempts, last_error, received_at
from webhook_events where processed_at is null order by received_at;
```

O que cada página de transação produziu — quantas chegaram, quantas foram
filtradas, quantas colidiram na chave de dedup, quantas entraram, e a convenção
de sinal observada:

```sql
select event_type, received_at, jsonb_pretty(payload -> '_convencao')
from webhook_events order by received_at desc limit 3;
```

**Isto mora no banco, não em `console.log`, de propósito:** a saída de console
das Edge Functions não é legível por SQL nem pelo CLI desta versão, só pelo
dashboard. A primeira instrumentação de convenção rodou e não houve como ler o
resultado.

Reprocessar um item (o worker drena a fila; não recebe corpo):

```sql
insert into webhook_events (event_id, event_type, item_id, payload)
values ('reprocessa-<motivo>', 'transactions/created', '<item-id>', '{}'::jsonb);
```

```bash
curl -X POST "$SUPABASE_URL/functions/v1/pluggy-sync-worker" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY"
```
