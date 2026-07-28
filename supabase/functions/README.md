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
| `pluggy-connect-token` | `true` | ✅ Deployada. **Exercitada de verdade** — o widget carregou e o fluxo completou no simulador. |
| `pluggy-webhook` | **`false`** | Escrita. Não deployada. |
| `pluggy-sync-worker` | `true` | Escrita. Não deployada, nunca rodou. |

`_shared/pluggy.ts` concentra a troca de `CLIENT_ID`/`CLIENT_SECRET` pela apiKey
(com cache por isolate) e o `GET` autenticado — duas funções com caches
independentes acabariam estourando o rate limit de `/auth` por um caminho e não
pelo outro.

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
supabase functions deploy pluggy-connect-token pluggy-webhook pluggy-sync-worker
```

## Limitações conhecidas

- **Nada foi typecheckado localmente.** Deno não está instalado na máquina de
  desenvolvimento e `supabase functions serve` exige Docker: o `deploy` é a
  primeira compilação. Vale para as três.
- **O worker nunca rodou.** O mapeamento de status, de subtipo de conta e de
  sinal de valor segue a referência §7.1–7.4 e nada mais que isso o garante.
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
