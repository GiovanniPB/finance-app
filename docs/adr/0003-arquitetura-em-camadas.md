# ADR 0003 — Arquitetura em camadas e fluxo de dados

- Status: aceito
- Data: 2026-07-14

## Contexto

Precisamos de fronteiras claras entre UI, regras de negócio e acesso a dados,
alinhadas à arquitetura recomendada oficialmente pelo Flutter.

## Decisão

Cada feature se organiza em três camadas com fluxo unidirecional:

- **domain/** — entidades imutáveis (freezed), interfaces de repository e use
  cases (apenas quando há regra de negócio real). Não conhece Flutter, PowerSync
  nem Supabase.
- **data/** — implementações dos repositories. Leituras reativas via PowerSync
  (`watch`), escritas locais via `execute` (entram na fila de upload). Auth via
  Supabase. Mapeia linhas ↔ entidades na fronteira.
- **presentation/** — providers/notifiers do Riverpod expõem estado à UI.

Regra de dependência: `presentation → domain ← data`.

Erros recuperáveis fluem como `Result<T, Failure>` (nunca exceptions até a UI).

## Consequências

- `domain` testável isoladamente; `data` trocável (ex.: SQL→Drift) sem afetar o
  resto.
- Uploads de sync e abertura do banco dependem do SDK nativo do PowerSync e são
  cobertos por **testes de integração** (não por unidade) — por isso esses
  arquivos-glue são excluídos da métrica de cobertura unitária.
