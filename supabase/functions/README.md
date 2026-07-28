# Edge Functions — pipeline de Open Finance

Implementa o ADR 0005: **todo dado de Open Finance entra pelo servidor**. O
cliente nunca fala com a Pluggy a não ser pelo widget Connect, e mesmo aí só com
um token efêmero que uma função daqui emitiu.

```
Pluggy → Edge Function → Postgres → PowerSync (WAL) → SQLite local
```

## Estado

| Função | Estado |
|---|---|
| `pluggy-connect-token` | Escrita. **Não deployada, não exercitada contra a Pluggy.** |
| `pluggy-webhook` | Não existe. |
| `pluggy-sync-worker` | Não existe. |

O schema que elas alimentam já existe (migration `20260728033219`):
`open_finance_connections`, `webhook_events`, e as colunas `external_id` /
`description_raw` em `transactions`.

## Segredos

As funções leem do ambiente. **Nenhum valor mora no repo** — `env/*.json` é
git-ignored e isto aqui é servidor, não cliente.

| Variável | Origem | Quem já fornece |
|---|---|---|
| `PLUGGY_CLIENT_ID` | Dashboard da Pluggy → Application | você, via `secrets set` |
| `PLUGGY_CLIENT_SECRET` | idem | você, via `secrets set` |
| `SUPABASE_URL` | injetada pelo runtime | Supabase |
| `SUPABASE_ANON_KEY` | injetada pelo runtime | Supabase |

Configurar (roda **você**, para os valores não passarem pelo histórico de uma
conversa nem por um arquivo do repo):

```bash
supabase secrets set PLUGGY_CLIENT_ID=... PLUGGY_CLIENT_SECRET=...
```

Conferir o que está configurado, sem revelar valores:

```bash
supabase secrets list
```

## Deploy

```bash
supabase functions deploy pluggy-connect-token
```

`verify_jwt` está declarado em `supabase/config.toml` por função. A
`pluggy-connect-token` exige JWT; a `pluggy-webhook`, quando existir, será a
única com `verify_jwt = false` — quem a chama é a Pluggy, que não tem sessão do
Supabase, e a autenticação dela é o header secreto.

## Limitações conhecidas desta fatia

- **O TypeScript não foi typecheckado localmente.** Deno não está instalado na
  máquina de desenvolvimento, e `supabase functions serve` exige Docker. O
  primeiro `deploy` é também a primeira compilação.
- **Nada foi exercitado contra a Pluggy.** `POST /auth` e `POST /connect_token`
  seguem o contrato de `docs/pluggy-api-reference.md` §3.3 e §3.4, mas nenhuma
  chamada real aconteceu.
- **Não há cliente chamando a função.** O caminho no app (botão "Conectar banco",
  widget Connect, gravação de `open_finance_connections`) é a fatia seguinte. Sem
  ele, a função é alcançável só por `curl` com um JWT válido.
- **O cache da apiKey é por isolate.** Escala reciclando: cada isolate novo paga
  um `POST /auth`. É deliberado — persistir credencial de acesso total para
  economizar uma chamada seria trocar segurança por latência.

## Testar sem app, quando os segredos existirem

```bash
curl -i -X POST "$SUPABASE_URL/functions/v1/pluggy-connect-token" -H "Authorization: Bearer $JWT_DE_UM_USUARIO"
```

Resposta esperada: `200` com `{"accessToken":"..."}`. Sem `Authorization`, `401`.
