# Pluggy API — Referência Completa para Agentes de IA

> **Objetivo deste documento:** fornecer a um agente de IA (ou desenvolvedor) tudo o que é necessário para integrar a **Pluggy** com precisão — conceitos, autenticação, ciclo de vida de Item, endpoints, schemas de dados, webhooks, códigos de erro e regras operacionais. Todo o conteúdo foi extraído da documentação oficial (`docs.pluggy.ai`, `llms.txt` e as versões `.md` das páginas de referência).
>
> **Base URL:** `https://api.pluggy.ai`
> **Formato:** JSON em todos os requests/responses.
> **País-alvo:** Brasil (BR) — inclui Open Finance regulado, Pix, boletos, TED/DOC.
> **Índice oficial para IA:** `https://docs.pluggy.ai/llms.txt` (contém todas as páginas em Markdown + OpenAPI).

---

## 1. O que é a Pluggy

A Pluggy é uma plataforma de **open finance / agregação de dados financeiros**. Com uma única API você conecta contas dos seus usuários em instituições financeiras (bancos, corretoras, cartões) e recupera dados padronizados: contas, cartões de crédito, transações, investimentos, identidade, empréstimos, além de iniciação de pagamentos (Pix, Pix Automático, Smart Transfers, boletos).

Fluxo mental: **Client (você)** → autentica → cria/gerencia **Items** (conexões) → coleta **Products** (dados) → reage via **Webhooks**.

---

## 2. Conceitos fundamentais (glossário)

| Conceito | Definição |
|---|---|
| **Product (Produto)** | Dados padronizados de uma instituição com atributos específicos para um propósito. Ex.: `ACCOUNTS`, `CREDIT_CARDS`, `TRANSACTIONS`, `INVESTMENTS`, `IDENTITY`, `LOANS`, `PAYMENT_DATA`, `INVESTMENTS_TRANSACTIONS`, `BROKERAGE_NOTE`, `MOVE_SECURITY`. |
| **Connector (Conector)** | Integração com uma instituição financeira que recupera produtos com base no acesso do usuário. Cada conector tem um `id` numérico. |
| **Item** | Representação de **uma conexão** através de um conector, após o consentimento do usuário. É o ponto de entrada para acessar os produtos coletados. Identificado por UUID. |
| **API Key** | Segredo que autentica **todas** as chamadas server-side. Expira **2 horas** após criação. Gerada com `CLIENT_ID` + `CLIENT_SECRET`. Dá acesso total. |
| **Connect Token** | Segredo para uso **client-side** (ex.: no widget Pluggy Connect). Expira **30 minutos**. Acesso restrito a `GET /items/:id` e `GET /accounts?itemId`. Recomendação: 1 token por conexão. |
| **CLIENT_ID / CLIENT_SECRET** | Credenciais permanentes obtidas no Dashboard (`dashboard.pluggy.ai`). **Extremamente sensíveis** — nunca expor no client. |

---

## 3. Autenticação

### 3.1 Modelo em duas camadas

- **Server-side (API Key):** para tudo — coletar produtos, configurar webhooks, gerenciar items, pagamentos.
- **Client-side (Connect Token):** apenas para inicializar o widget e ler o item/contas recém-criados. Tentar acessar dados detalhados de produto com Connect Token retorna **`403 Forbidden`**.

### 3.2 Header de autenticação

Ambos os segredos são passados no header:

```
X-API-KEY: <apiKey ou connectToken>
```

A Pluggy valida automaticamente o escopo do token.

### 3.3 Criar API Key — `POST /auth`

**Request:**
```json
{
  "clientId": "f8c9b8f0-b8e2-4f0f-b8e2-4f0f8e2f0f8e2",
  "clientSecret": "UZzp2n7eMThpfZ74Xf7"
}
```

**Response 200:**
```json
{ "apiKey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." }
```

**Erros:** `401 CLIENT_KEYS_UNAUTHORIZED` (credenciais inválidas), `401 CLIENT_DISABLED` (cliente desabilitado).

> Reutilize a mesma API Key durante as 2h de validade — não chame `/auth` a cada request (há rate limit).

### 3.4 Criar Connect Token — `POST /connect_token`

Requer API Key no header. Serve para criar **ou atualizar** um item via widget.

**Request (criação):**
```json
{
  "options": {
    "webhookUrl": "https://example.com/webhook",
    "clientUserId": "My App UserId",
    "oauthRedirectUri": "https://pluggy.ai/demo",
    "avoidDuplicates": true
  }
}
```

**Request (atualização de item existente):** inclua `itemId` no nível raiz. Sem ele, a atualização via widget é bloqueada por segurança.
```json
{
  "itemId": "5e9f8f8f-f8f8-4f8f-8f8f-8f8f8f8f8f8f",
  "options": { "clientUserId": "My App UserId" }
}
```

**Response 200:**
```json
{ "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..." }
```

**Opções (`ItemOptions`):**
- `clientUserId` — seu identificador externo do usuário (ID, UUID, email). Fica disponível em todo item criado com esse token. Use para rastreabilidade ponta a ponta.
- `webhookUrl` — envia todos os eventos do item para essa URL (além dos webhooks configurados no nível do cliente).
- `oauthRedirectUri` — URL de redirecionamento após o fluxo OAuth.
- `avoidDuplicates` — evita criar novo item se já existir um com as mesmas credenciais.

**Erros:** `403` (não autenticado), `404 ITEM_NOT_FOUND` (itemId de atualização não encontrado).

---

## 4. Ciclo de vida do Item

Se você usar o **widget Pluggy Connect**, a maior parte deste fluxo é gerenciada automaticamente. Se integrar direto pela API, precisa tratar os estados abaixo.

### 4.1 `status` do Item (visão macro da saúde da conexão)

| Valor | Significado |
|---|---|
| `UPDATING` | Sincronização em andamento. Consultar novamente em alguns segundos. |
| `LOGIN_ERROR` | Última execução falhou por credenciais inválidas. **Não** é auto-sincronizado até novas credenciais serem enviadas. Requer update manual com novas credenciais. |
| `OUTDATED` | Parâmetros validados, mas houve erro na última execução. Pode ser retentado. Verificar `executionStatus`. |
| `WAITING_USER_INPUT` | Aguardando input do usuário (comum em conectores MFA). |
| `UPDATED` | Última sincronização concluída com sucesso; dados disponíveis. |

### 4.2 `executionStatus` — estados transitórios (execução em andamento)

`CREATED`, `LOGIN_IN_PROGRESS`, `LOGIN_MFA_IN_PROGRESS`, `ACCOUNTS_IN_PROGRESS`, `CREDITCARDS_IN_PROGRESS`, `TRANSACTIONS_IN_PROGRESS`, `INVESTMENT_TRANSACTIONS_IN_PROGRESS`, `PAYMENT_DATA_IN_PROGRESS`, `IDENTITY_IN_PROGRESS`, `MERGING`.

> Os estados seguem a ordem de coleta: login → accounts → credit cards → transactions → investment transactions → payment data → identity → merging (persistência). Cada etapa implica que a anterior foi concluída ou pulada.
> **Atenção:** `LOGIN_IN_PROGRESS` pode durar até **5 minutos** em algumas instituições.

### 4.3 `executionStatus` — estados finais de sucesso

| Valor | Significado |
|---|---|
| `SUCCESS` | Execução concluída, todos os produtos coletados. |
| `PARTIAL_SUCCESS` | Concluída, mas alguns produtos falharam. Verificar `statusDetail` do item. |

### 4.4 `executionStatus` — estados finais de erro

| Valor | Significado |
|---|---|
| `ERROR` | Erro inesperado na conexão. |
| `MERGE_ERROR` | Dados coletados, mas erro ao persistir nos registros da Pluggy. |
| `INVALID_CREDENTIALS` | Credenciais incorretas. |
| `ALREADY_LOGGED_IN` | Sessão ativa na instituição impediu novo login. |
| `SITE_NOT_AVAILABLE` | Site da instituição indisponível/manutenção. |
| `INVALID_CREDENTIALS_MFA` | Token MFA (2ª etapa) incorreto ou expirado. |
| `USER_INPUT_TIMEOUT` | Tempo para fornecer o MFA expirou. |
| `ACCOUNT_LOCKED` | Conta bloqueada na instituição. Usuário precisa contatar o banco. |
| `ACCOUNT_NEEDS_ACTION` | Ação manual necessária (aceitar novos termos, atualizar dados etc.). |
| `USER_NOT_SUPPORTED` | Tipo de conta não suportado pelo conector. |
| `ACCOUNT_CREDENTIALS_RESET` | Instituição exige reset das credenciais (senha expirada/nova política). |
| `CONNECTION_ERROR` | Falha ao estabelecer conexão com o site. |
| `USER_AUTHORIZATION_NOT_GRANTED` | Usuário não autorizou o dispositivo/conector. |
| `USER_AUTHORIZATION_REVOKED` | Usuário revogou o consentimento na instituição. |

### 4.5 `executionStatus` — estados intermediários (requerem ação)

| Valor | Significado |
|---|---|
| `WAITING_USER_INPUT` | Login inicial OK; instituição pede input extra (ex.: token MFA). Enviar via `POST /items/{id}/mfa`. |
| `USER_AUTHORIZATION_PENDING` | Usuário precisa autorizar manualmente no app/dispositivo. Após resolver, a Pluggy prossegue automaticamente em alguns minutos. |

### 4.6 Três tipos de fluxo de login por conector

1. **Sem MFA:** apenas credenciais. Se OK → `UPDATED`/`SUCCESS` (ou `PARTIAL_SUCCESS`); se erro fatal → `OUTDATED`/`ERROR`; se credenciais erradas → `LOGIN_ERROR`. Items com credenciais válidas são **auto-sincronizados 1x/dia por padrão**.
2. **MFA de 1 etapa** (credencial com `mfa: true`): usuário fornece o MFA junto das credenciais. **Não** é auto-atualizável (exige input a cada execução). Exceção: alguns conectores (ex.: Banco do Brasil PJ) permitem sync contínuo após autorização inicial do dispositivo. Reenviar o **mesmo** MFA da última execução → `400`.
3. **MFA de 2 etapas** (conector com `mfa: true` na base): após credenciais corretas, item vai para `WAITING_USER_INPUT`; usuário envia o código; execução retoma. Não auto-atualizável. Exceção: **Nubank** (após autorização inicial do dispositivo).

### 4.7 Retenção e limpeza automática de dados

Emite o webhook `item/deleted` sempre que um item é removido por qualquer processo:

| Cenário | Quando dispara | O que acontece |
|---|---|---|
| Item deletado pelo cliente | Imediato, em `DELETE /items/{id}` | Item marcado como deletado, credenciais apagadas, consentimento Open Finance revogado (quando aplicável), autorizações OAuth expiradas, dados apagados permanentemente. |
| Item Sandbox sem uso | `updatedAt` > **30 dias** | Item e dados removidos permanentemente. Recriar para continuar testando. |
| Conector descontinuado | **30 dias** após deprecação | Todos os items do conector são deletados (mesmo processo do delete manual). |

> **Ação prática:** ao receber aviso de deprecação de conector, você tem 30 dias para migrar os usuários. Assine `item/deleted` para reagir a deleções automáticas.

---

## 5. Endpoints — Items

Todos exigem API Key (`X-API-KEY`), exceto `GET /items/{id}` que também aceita Connect Token.

### 5.1 Criar Item — `POST /items`

Cria o item e sincroniza os produtos usando as credenciais enviadas.

**Como montar `parameters`:** consulte `GET /connectors/{id}` para obter o array `credentials`. Cada credencial vira um par chave-valor: a **chave** é o `name` da credencial; o **valor** é o input do usuário.

Exemplo de definição de credenciais do conector:
```json
{ "credentials": [
  { "name": "agency",  "type": "number", "validation": "^\\d{4}$" },
  { "name": "account", "type": "number", "validation": "^\\d{4,6}$" },
  { "name": "password","type": "number", "validation": "^\\d{6}$" }
]}
```
Parâmetros a enviar:
```json
{ "agency": "1234", "account": "123456", "password": "123456" }
```

**Request body (`CreateItem`):**
```json
{
  "connectorId": 2,
  "parameters": { "user": "user-ok", "password": "password-ok" },
  "webhookUrl": "https://example.com/webhook",
  "clientUserId": "opcional",
  "oauthRedirectUri": "opcional (obrigatório em conectores OAuth)",
  "products": ["ACCOUNTS", "TRANSACTIONS"],
  "avoidDuplicates": true
}
```
- **Obrigatórios:** `connectorId`, `parameters`.
- `products` — se omitido, coleta todos os produtos suportados; informe para restringir.

**Credenciais criptografadas (camada extra de segurança):** solicite à equipe de operações a criação de uma **RSA Public Key** para sua aplicação. Criptografe o objeto `parameters`, faça Base64 e envie a **string** resultante como `parameters`. Padding: **`RSA_PKCS1_OAEP_PADDING`**. Vale também para updates.

**Response 200:** objeto `Item` (ver schema na §7.1).

**Erros:**
- `400 CONNECTOR_VALIDATION_ERROR` — parâmetro faltando ou inválido (inclui MFA faltando). Retorna `details[]` com `parameter`.
- `400 ITEM_USER_ALREADY_EXISTS` — com `avoidDuplicates`, já existe item com as mesmas credenciais (retorna `items[]`).
- `409 ITEM_CREATION_LIMIT_EXCEEDED` — limite do plano atingido (retorna `data.itemsLimit`).

> **Plano Free:** só pode criar items via **widget Pluggy Connect** (`CREATE_ITEMS_API_FREE_DISABLED` ao tentar via API).

### 5.2 Recuperar Item — `GET /items/{id}`

Retorna o recurso `Item`. Aceita API Key **ou** Connect Token. **Sempre chame este endpoint como primeiro passo ao processar webhooks de item**, para obter o estado mais recente (não confie apenas no payload do webhook).

### 5.3 Atualizar / re-sincronizar Item — `PATCH /items/{id}`

Dispara nova sincronização. Credenciais são **opcionais**: se omitidas, usa as armazenadas.

**Body — sem atualizar credenciais:** `{}`
**Body — atualizando credenciais:** `{ "user": "user-ok", "password": "password-ok" }`
**Body — enviando apenas MFA de 1 etapa:** `{ "token": "123456" }`

Campos aceitos (`UpdateItem`): `parameters` (objeto ou string criptografada), `clientUserId`, `webhookUrl`, `products`.

**Erros relevantes:**
- `400 MFA_PARAMERTER_WAS_ALREADY_USED_ERROR` — reenvio do mesmo MFA da última execução.
- `400 CONNECTOR_REQUIRED_PARAMETER_VALIDATION_ERROR` — parâmetro (ex.: `token`) precisa ser renovado.
- `400 TOO_MANY_CONSECUTIVE_ERRORS` — mais de 5 sincronizações falhas; contatar suporte.
- `400 TOO_MANY_CONSECUTIVE_LOGIN_FAILURES` — cooldown após N erros de login (retorna `readableBackoffTime`, `canRetryAfterDate`).
- `409 CLIENT_IS_UPDATING_BEFORE_ALLOWED_FREQUENCY` — updates permitidos no máximo a cada `minUpdateFrequencyAllowedInHours` horas.
- `404 ITEM_NOT_FOUND`.

> **Rate limit:** `PATCH /items` = **20 req/min por IP**. Para updates diários, **use auto-sync**, não `PATCH`.

### 5.4 Deletar Item — `DELETE /items/{id}`

Apaga o item pelo identificador primário. Dispara `item/deleted`; credenciais e dados são removidos permanentemente e o consentimento Open Finance é revogado.

### 5.5 Enviar MFA — `POST /items/{id}/mfa`

Quando o item está em `WAITING_USER_INPUT`, submete o valor de MFA. O nome do parâmetro esperado é indicado no campo `parameter` do item.

**Erros de MFA:**
| Código | Significado |
|---|---|
| `ITEM_MFA_ALREADY_PROVIDED` | MFA já foi fornecido; nada a fazer. |
| `ITEM_MFA_NOT_FOUND` | Item não está aguardando MFA. |
| `ITEM_MFA_EXPIRED` | MFA expirou; iniciar novo update. |
| `ITEM_MFA_PARAMETER_EXPECTED_MISMATCH` | Item espera outro parâmetro (`paramName`). Ajustar payload. |
| `MFA_PARAMERTER_WAS_ALREADY_USED_ERROR` | Valor igual ao da última execução; enviar novo. |

### 5.6 Consents — `GET /items/{itemId}/consents` e `GET /consents/{id}`

Recuperam os consentimentos concedidos ao item (relevante em Open Finance regulado, onde o consentimento tem prazo de expiração — ver `consentExpiresAt` no Item).

---

## 6. Auto-sync (sincronização automática)

Items com credenciais válidas e sem exigência de MFA por execução são sincronizados automaticamente pela Pluggy **1x por dia por padrão**. O campo `nextAutoSyncAt` indica a próxima execução (ou `null` se desabilitado). Use auto-sync em vez de `PATCH /items` para atualizações recorrentes — respeita rate limits e evita bloqueios na instituição.

---

## 7. Schemas de dados (produtos)

### 7.1 Item

Campos principais do objeto `Item` (retornado por create/retrieve/update):

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string (UUID) | Identificador primário. |
| `connector` | Connector | Conector usado (ver §7.2). |
| `status` | string | Ver §4.1. |
| `executionStatus` | string | Ver §4.2–4.5. |
| `error` | object\|null | `{ code, message, providerMessage, attributes }`. |
| `parameter` | ConnectorCredential\|null | Credencial/MFA atualmente solicitada. |
| `userAction` | object\|null | `{ instructions, attributes, expiresAt }` — ação manual do usuário. |
| `webhookUrl` | string\|null | URL de notificação específica do item. |
| `clientUserId` | string\|null | Seu identificador externo do usuário. |
| `createdAt` / `updatedAt` | date-time | Criação / última modificação. |
| `lastUpdatedAt` | date-time | Última sincronização bem-sucedida. |
| `statusDetail` | StatusDetail\|null | Detalhe por produto (presente em `PARTIAL_SUCCESS` ou com warnings). |
| `nextAutoSyncAt` | date-time\|null | Próximo auto-sync. |
| `consecutiveFailedLoginAttempts` | number | Nº de execuções consecutivas com `LOGIN_ERROR`. |
| `consentExpiresAt` | date-time\|null | Expiração do consentimento (Open Finance). |
| `products` | string[] | Produtos coletados pelo item. |

**`StatusDetail`** contém, por produto (`accounts`, `creditCards`, `transactions`, `investments`, `identity`, `investmentsTransactions`, `paymentData`, `loans`), um objeto `{ isUpdated, lastUpdatedAt, warnings[] }`. Cada warning: `{ code, message, providerMessage }`.

### 7.2 Connector

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | number | Identificador do conector. |
| `name` | string | Nome da instituição. |
| `institutionUrl`, `imageUrl`, `primaryColor` | string | Branding. |
| `type` | string | Ex.: `PERSONAL_BANK`, `BUSINESS_BANK`. |
| `country` | string | Ex.: `BR`. |
| `credentials` | ConnectorCredential[] | Parâmetros exigidos para conectar. |
| `hasMFA` | boolean | Conector exige MFA. |
| `products` | string[] | Produtos suportados. |
| `oauth` / `oauthUrl` | boolean / string | Se requer fluxo OAuth. |
| `resetPasswordUrl` | string | URL de reset de senha na instituição. |
| `health` | ConnectorHealth | `{ status: ONLINE\|OFFLINE\|UNSTABLE, stage, details? }`. |
| `isOpenFinance` | boolean | Usa APIs reguladas do Open Finance. |
| `supportsPaymentInitiation` / `supportsScheduledPayments` / `supportsSmartTransfers` / `supportsBoletoManagement` / `supportsAutomaticPix` | boolean | Capacidades de pagamento. |

**`ConnectorCredential`:** `{ name, label, type (text|password|number|image|select), assistiveText, data, placeholder, validation (regex), validationMessage, mfa (bool), options[] }`.

**`ConnectorHealth.details`** (só com `?healthDetails=true`): `connectionRateLast6Hours` (0–100), `connectionsLast6Hours`.

### 7.3 Account — `GET /accounts?itemId={itemId}` e `GET /accounts/{id}`

Parâmetros da lista: `itemId` (obrigatório, UUID), `type` (opcional: `BANK` | `CREDIT`). Resposta paginada por página: `{ page, total, totalPages, results[] }`.

Campos de `Account`:

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | Identificador. |
| `type` | `BANK` \| `CREDIT` | Tipo. |
| `subtype` | `SAVINGS_ACCOUNT` \| `CHECKING_ACCOUNT` \| `CREDIT_CARD` | Subtipo. |
| `number` | string | Identificador externo (ex.: `0001/12345-0`). |
| `name` / `marketingName` | string | Nome descritivo / comercial. |
| `balance` | number | Saldo (valor absoluto; para cartão representa o valor da fatura). |
| `itemId` | string (UUID) | Item associado. |
| `taxNumber` | string | CPF/CNPJ do titular. |
| `owner` | string | Nome do titular. |
| `currencyCode` | string | Ex.: `BRL`. |
| `bankData` | BankData | Só para `BANK`. |
| `creditData` | CreditData | Só para `CREDIT`. |

**`BankData`:** `transferNumber`, `closingBalance`, `automaticallyInvestedBalance`, `overdraftContractedLimit`, `overdraftUsedLimit`, `unarrangedOverdraftAmount`.

**`CreditData`:** `level`, `brand`, `balanceCloseDate`, `balanceDueDate`, `availableCreditLimit`, `balanceForeignCurrency`, `minimumPayment`, `creditLimit`, `status` (`ACTIVE`|`BLOCKED`|`CANCELLED`), `holderType` (`MAIN`|`ADDITIONAL`), `disaggregatedCreditLimits[]`, `additionalCards[]`.

**Real-time balance — `GET /accounts/{id}/balance`:** busca o saldo direto na instituição sem disparar sync completo do item. Útil entre ciclos de sincronização.

### 7.4 Transaction — `GET /v2/transactions?accountId={accountId}` (paginação por cursor)

> Este é o endpoint recomendado. A versão paginada por página (`GET /transactions`) está **deprecada até 2026-12-31**; migre para `/v2/transactions`.

**Estratégia recomendada:** as transações devem ser **copiadas para o seu sistema**. Use este endpoint **uma vez por sincronização**, acionado pelos webhooks `transactions/created|updated|deleted`, paginando com o máximo de registros por página (**500**, que é o default).

**Query params:**
- `accountId` (obrigatório, UUID)
- `ids` — lista separada por vírgula (máx. **500** UUIDs). Usado para buscar transações citadas em `transactions/updated`.
- `dateFrom` / `dateTo` — filtro por data da transação (`yyyy-mm-dd`). `dateFrom` **não** pode ser usado junto com `createdAtFrom`.
- `createdAtFrom` — transações criadas a partir de (`yyyy-mm-ddThh:mm:ss.000Z`). Usado com `createdTransactionsLink` do webhook.
- `after` — cursor da próxima página (campo `next` da resposta anterior).

**Resposta (`CursorPageResponseTransactions`):**
```json
{
  "results": [ /* Transaction[] */ ],
  "next": "?accountId=...&after=<cursor base64>"  // null quando não há mais páginas
}
```

Campos de `Transaction`:

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | Identificador. |
| `description` | string | Descrição limpa/normalizada. |
| `descriptionRaw` | string\|null | Descrição original da instituição. |
| `currencyCode` | string | ISO da moeda. |
| `amount` | number | Valor. |
| `amountInAccountCurrency` | number | Valor na moeda da conta (se diferente). |
| `date` | date-time | Data da transação. |
| `type` | `DEBIT` \| `CREDIT` | Direção do fluxo pela ótica do titular. **Normalizado:** em cartão, compras = `DEBIT`, pagamentos da fatura = `CREDIT`. |
| `balance` | number\|null | Saldo após a transação (pode ser null). |
| `status` | `POSTED` \| `PENDING` | Liquidada / autorizada mas não liquidada. |
| `category` / `categoryId` | string | Categoria e ID (ver Categories). |
| `paymentData` | PaymentData | Dados de pagador/recebedor. |
| `creditCardMetadata` | CreditCardMetadata | Metadados de cartão. |
| `merchant` | Merchant | Estabelecimento extraído. |
| `operationType` / `operationTypeAdditionalInfo` | string\|null | Só em conectores Open Finance. |
| `providerId` | string | ID do provedor. **Só em conexões reguladas (Open Finance)**; igual para a mesma conta em items diferentes. |
| `providerCode` | string | Código da instituição (NSU etc.). Só em reguladas e alguns conectores. |
| `accountId` | string (UUID) | Conta da transação. |
| `order` | number | Posição sequencial no mesmo dia. |
| `createdAt` / `updatedAt` | date-time | Ingestão / última atualização na Pluggy. |

**`PaymentData`:** `payer` / `receiver` (`PaymentDataParticipant`: `documentNumber {type: CPF|CNPJ, value}`, `name`, `accountNumber`, `branchNumber`, `routingNumber` COMPE, `routingNumberISPB`), `reason`, `referenceNumber`, `receiverReferenceId`, `paymentMethod` (`PIX`|`TED`|`DOC`|`TEV`|`BOLETO`), `boletoMetadata` (`digitableLine`, `barcode`, `baseAmount`, `interestAmount`, `penaltyAmount`, `discountAmount`).

**`CreditCardMetadata`:** `installmentNumber`, `totalInstallments`, `totalAmount`, `feeType`, `otherCreditsType`, `purchaseDate`, `payeeMCC`, `cardNumber`, `billId`, `billForecastDate`.

**`Merchant`:** `name`, `businessName`, `cnpj`, `cnae`.

**Atualizar categoria — `PATCH /transactions/{id}`:** atualiza `categoryId` da transação.

### 7.5 Investment — `GET /investments?itemId={itemId}` e `GET /investments/{id}`

Recupera investimentos coletados do item. Transações de investimento: `GET /investments/{id}/transactions`. (Campos como `code`, `name`, `balance`, `amount`, `quantity`, `type`, `subtype`, `annualRate`, `value`, `dueDate`, entre outros; consulte a página específica de Investments para o schema completo por tipo de ativo.)

### 7.6 Outros produtos e recursos

- **Identity:** `GET /identity?itemId={itemId}` e `GET /identity/{id}` — dados cadastrais do titular.
- **Credit Card Bills:** `GET /bills?accountId={accountId}` e `GET /bills/{id}`.
- **Loans:** `GET /loans?itemId={itemId}` e `GET /loans/{id}`.
- **Categories:** `GET /categories` (filtrável por `parentId`), `GET /categories/{id}`; regras de categoria: list/create/delete em `/categories/rules`.
- **Merchants:** `POST /merchants` (buscar por lista de CNPJs).
- **Connectors:** `GET /connectors` (todos), `GET /connectors/{id}`, `POST /connectors/{id}/validate`.

---

## 8. Webhooks

Notificação HTTP `POST` (JSON) para uma URL **HTTPS** sua, disparada por eventos. Localhost não é aceito (use ngrok/túnel).

### 8.1 Como assinar

- **Instância de webhook** (`POST /webhooks`): assina **todos** os casos de um tipo de evento, no nível do cliente.
- **`webhookUrl`** ao criar Item / Connect Token / Payment Request: recebe **todos** os eventos, mas **restritos àquele recurso** (item específico ou items daquele token).

Endpoints de gestão: `GET /webhooks`, `POST /webhooks`, `GET /webhooks/{id}`, `PATCH /webhooks/{id}`, `DELETE /webhooks/{id}`.

Use `event: "all"` para receber todos os eventos.

### 8.2 Eventos de dados

| Evento | Descrição |
|---|---|
| `item/created` | Item criado e conectado com sucesso. |
| `item/updated` | Item atualizado e sincronizado com sucesso. |
| `item/deleted` | Item deletado (inclui deleções automáticas). |
| `item/error` | Erro na execução (inclui `USER_AUTHORIZATION_PENDING`). |
| `item/waiting_user_input` | Bloqueado aguardando input (MFA). |
| `item/waiting_user_action` | Aguardando ação/autorização do usuário no dispositivo (app do banco, QR code). |
| `item/login_succeeded` | Login OK; coletando dados. (Retentado só 3x, sem backoff.) |
| `connector/status_updated` | Conector mudou de status (ONLINE/UNSTABLE/OFFLINE). Informa `connectorId` e `data.status`. |
| `transactions/created` | Novas transações. Use `createdTransactionsLink` para buscá-las. |
| `transactions/updated` | Transações atualizadas; buscar via `/v2/transactions?ids=...`. |
| `transactions/deleted` | IDs de transações deletadas após merge. |

> Webhooks de transação só disparam quando há mudança de dados. Sem novas transações, `transactions/created` não dispara.

### 8.3 Eventos de pagamento

- **Payment Intent:** `payment_intent/created`, `/completed`, `/waiting_payer_authorization`, `/error`; `payment_request/updated`.
- **Scheduled Payment:** `scheduled_payment/created`, `/completed`, `/error`, `/canceled`.
- **Automatic PIX:** `automatic_pix_payment/created`, `/completed`, `/error`, `/canceled`.
- **Smart Transfer:** `smart_transfer_preauthorization/completed`, `/error`; `smart_transfer_payment/completed`, `/error`.

### 8.4 Payload — parâmetros comuns

- `event` — nome do evento.
- `eventId` — ID do evento (o mesmo quando enviado a múltiplos endpoints).
- `clientUserId` — seu ID de usuário.
- `triggeredBy` — quem disparou (exceto `item/deleted`, `connector/status_updated`, `transactions/deleted`): `USER` (Connect Token), `CLIENT` (API Key), `SYNC` (auto-sync), `INTERNAL` (suporte Pluggy).
- ID da entidade conforme o tipo: `itemId`, `transactionIds`, `connectorId`, `paymentRequestId`, etc.

**Exemplo `item/created`:**
```json
{ "event":"item/created", "eventId":"d876...", "itemId":"a5c7...", "triggeredBy":"USER", "clientUserId":"client-user-id" }
```

**Exemplo `item/error`:**
```json
{ "event":"item/error", "eventId":"d876...", "itemId":"d161...",
  "error": { "code":"USER_INPUT_TIMEOUT", "message":"User requested input had expired", "parameter":"token" },
  "triggeredBy":"USER", "clientUserId":"client-user-id" }
```

**Exemplo `transactions/created`:**
```json
{ "itemId":"de7b...", "event":"transactions/created", "eventId":"4e69...",
  "accountId":"0d5a...", "transactionsCount":332,
  "transactionsMinDate":"2025-02-12T15:00:01.000Z",
  "transactionsCreatedAtFrom":"2025-02-13T17:21:53.719Z",
  "createdTransactionsLink":"https://api.pluggy.ai/transactions?accountId=0d5a...&createdAtFrom=2025-02-13T17:21:53.719Z" }
```

### 8.5 Regras de entrega e boas práticas

- **Responda 2XX em menos de 5 segundos** (sucesso). Qualquer outro status ou timeout = falha.
- **Processe DEPOIS de responder:** retorne 2XX imediatamente e faça o processamento pesado em background, para não gerar retries indevidos.
- **Retries:** até 3 tentativas seguidas; se falhar, nova rodada após 1h (3 tentativas) e uma final após +2h (3 tentativas) — **até 9 no total**. Exceção: `item/login_succeeded` (só 3, sem backoff).
- **Para eventos de item:** o primeiro passo do processamento deve ser `GET /items/{id}` para pegar o estado mais recente, em vez de confiar no payload.
- **IP whitelist:** as requisições da Pluggy vêm de `52.67.145.81`.
- **Headers customizados:** ao criar/atualizar webhook via API, envie um objeto `headers` (ex.: `Authorization`, `X-CLIENT-ID`). Só configurável via API (dados sensíveis).

```json
{ "url": "https://example.com/webhook", "event": "all",
  "headers": { "Authorization": "My API key", "X-CLIENT-ID": "extra" } }
```

---

## 9. Rate limits

Contagem por **minuto por IP**, por endpoint (limites independentes). Excedido → `429 Too Many Requests`.

| Endpoint | Máx req/min/IP |
|---|---|
| `POST /auth` | 360 |
| `GET /transactions` ou `GET /transactions/{id}` | 360 |
| `GET /investments` ou `GET /investments/{id}` | 360 |
| `GET /investments/{id}/transactions` | 360 |
| `PATCH /items` | **20** (updates manuais; para diário use auto-sync) |

**Resposta 429:**
```json
{ "message": "Too many requests. Please try again later (see Retry-After header in seconds)", "code": 429 }
```
**Headers:** `RateLimit-Limit`, `RateLimit-Reset` (segundos até resetar), `Retry-After` (sempre 60).

**Para evitar:** reutilize a API Key (não chame `/auth` repetidamente), limite paralelismo em batches, adicione espera entre chamadas, respeite `RateLimit-Reset`.

---

## 10. Erros — referência rápida

### 10.1 Estrutura padrão de erro (`GlobalErrorResponse`)
```json
{ "code": 500, "codeDescription": "INTERNAL_SERVER_ERROR", "message": "Internal Server Error", "data": {} }
```
Sempre inspecione `codeDescription` para distinguir programaticamente o erro.

### 10.2 Erros de criação/atualização de Item

| Código | Ação sugerida |
|---|---|
| `PARAMETERS_NOT_PROVIDED` | Enviar as credenciais para sincronizar. |
| `ITEM_ALREADY_UPDATING` / `ITEM_IS_ALREADY_UPDATING` | Aguardar a execução atual terminar (evita sessões múltiplas na instituição). |
| `CLIENT_IS_UPDATING_BEFORE_ALLOWED_FREQUENCY` | Respeitar a frequência mínima contratada entre updates. |
| `CREATE_ITEMS_API_FREE_DISABLED` | Plano Free só cria via widget Connect. |
| `SANDBOX_CLIENT_ITEM_UPDATE_NOT_ALLOWED` | Plano só permite atualizar items Sandbox. |
| `TOO_MANY_CONSECUTIVE_ERRORS` | >5 falhas; contatar suporte. |
| `ITEM_CREATION_LIMIT_EXCEEDED` | Limite de items do plano atingido. |
| `CLIENT_HAS_ITEM_UPDATES_DISABLED` | Updates desabilitados; contatar suporte. |
| `ITEM_ORIGINAL_CONNECTED_WITH_DIFFERENT_ACCOUNT` | Usar a conta original da conexão. |
| `CONNECTOR_REQUIRED_PARAMETER_VALIDATION_ERROR` | Renovar o parâmetro solicitado. |
| `LAST_EXECUTION_HAD_LOGIN_ERROR` | Enviar novas credenciais. |
| `TOO_MANY_CONSECUTIVE_LOGIN_FAILURES` | Aguardar cooldown antes de retentar. |
| `CONNECTOR_OFFLINE` | Conector indisponível; tentar mais tarde. |

### 10.3 Erros de MFA
Ver §5.5.

---

## 11. Sandbox

A Pluggy oferece conector Sandbox (**Pluggy Bank / MeuPluggy**) para testes sem uma instituição real, cobrindo os diversos estados do fluxo (sucesso, login error, MFA, waiting user input). Items Sandbox são removidos após 30 dias de inatividade. Consulte `docs/sandbox.md` para credenciais de teste que forçam cada cenário.

---

## 12. SDKs oficiais

Há SDKs server-side para acelerar a integração:

- **Node.js:** `pluggy-sdk` (npm)
- **Java**
- **C# / .NET**

Exemplo (Node — criar Connect Token):
```js
const pluggy = require('pluggy-sdk');
const client = new pluggy.PluggyClient({ clientId: 'YOUR_CLIENT_ID', clientSecret: 'YOUR_CLIENT_SECRET' });
const { accessToken } = await client.createConnectToken();
```

Exemplo (Node — criar Item e buscar contas):
```js
const item = await client.createItem(2, { user: 'user-ok', password: 'password-ok' });
const { results: accounts } = await client.fetchAccounts(item.id);
```

Também há **MCP Server** e **AI Skills** oficiais da Pluggy (ver `docs/mcp.md` e `docs/ai-skills.md`), úteis para agentes.

---

## 13. Fluxo de integração recomendado (resumo operacional)

1. **Server:** `POST /auth` com `CLIENT_ID`/`CLIENT_SECRET` → obter `apiKey` (cache por até 2h).
2. **Server:** `POST /connect_token` com a API Key → obter `accessToken` (1 por conexão; validade 30 min). Inclua `clientUserId` e `webhookUrl`.
3. **Client:** inicializar o **Pluggy Connect Widget** com o `accessToken`. O usuário escolhe a instituição, consente e autentica (MFA/OAuth tratados pelo widget). Capture o `itemId` no evento `onSuccess`.
4. **Server:** ao receber `item/created`/`item/updated`, faça `GET /items/{id}` para confirmar `status: UPDATED` / `executionStatus: SUCCESS`.
5. **Server:** colete dados — `GET /accounts?itemId=...`, depois `GET /v2/transactions?accountId=...` (paginando via `next`), `GET /investments?itemId=...`, `GET /identity?itemId=...`, etc.
6. **Sincronização contínua:** confie no **auto-sync** (1x/dia). Reaja a `transactions/created|updated|deleted` para manter sua base espelhada. Evite `PATCH /items` em cadência alta (limite 20/min).
7. **Manutenção:** trate `item/error`, `item/login_error`, `item/waiting_user_input` reengajando o usuário (novo Connect Token com `itemId` para update). Assine `item/deleted` para deleções automáticas.

---

## 14. Notas de precisão para o agente

- **Nunca** exponha `CLIENT_SECRET` ou API Key no client. No client, use apenas Connect Token.
- **Valores monetários** vêm em unidades da moeda (não centavos) como `number` (double); confira `currencyCode`.
- **Campos `providerId`/`providerCode`** só existem em conexões **Open Finance reguladas** (e `providerCode` em alguns conectores) — não dependa deles em conexões diretas.
- **Transações são para copiar**, não para consultar em tempo real por request de usuário; use webhooks + espelhamento local.
- **Sempre** re-buscar o Item via `GET /items/{id}` ao processar webhooks de item.
- **Datas** em ISO 8601 UTC (`...T00:00:00.000Z`). Filtros de transação por data usam `yyyy-mm-dd`.
- Ao integrar novos recursos, consulte primeiro `https://docs.pluggy.ai/llms.txt` e a página `.md` correspondente — cada página de referência inclui o **OpenAPI completo** do endpoint.

---

*Fontes: documentação oficial Pluggy — `docs.pluggy.ai` (Glossary, Authentication, Item lifecycle, Webhooks, Rate limits) e API Reference (`auth-create`, `connect-token-create`, `items-create`, `items-update`, `accounts-list`, `transactions-list-by-cursor`), via índice `llms.txt`. Consolidado para uso por agentes de IA.*
